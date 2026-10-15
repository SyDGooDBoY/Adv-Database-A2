# How to test this module

Two test suites, answering two different questions. Run both after any change.

| Suite | Question it answers | Command |
|---|---|---|
| `verify.mjs` | Does my module work on its own? | `node verify.mjs` |
| `integration.mjs` | Does the whole team's code work together? | `node integration.mjs` |

One-time setup: `pnpm install` in this directory.

---

## 1. Single-module test (`verify.mjs`)

Loads `00_shared_setup`, then the nine scripts of this module, runs the five
pipeline calls, runs `08_validation_tests.sql`, and asserts the result. No
database server is needed: PGlite is a real PostgreSQL build compiled to
WebAssembly, so plpgsql bodies, constraints, indexes and upserts are executed for
real ([ElectricSQL 2025](https://electric-sql.com/primitives/pglite)).

Expected output ends with `ALL CHECKS PASSED` and these numbers:

```
published KYC events: 9
published AML events: 10
registered findings: 3
verification cases: 2
AML cases: 1
exception fact rows: 3
```

**Why this is not enough on its own.** It runs only my module, so it cannot see a
clash with another member's code: a duplicate object name, a shared table written
in an incompatible way, or a change to data my rules depend on.

---

## 2. Cross-module integration test (`integration.mjs`)

Runs the whole team's code in dependency order and reports what fails.

```
Phase 1  shared setup (00-49)                     12 steps
Phase 2  every member's scripts, tests deferred    30 steps
Phase 3  pipeline steps not triggered by scripts    7 steps
Phase 3b what each layer holds                      6 assertions
Phase 4  every member's validation file             5 steps
Phase 5  my report, measured last                   6 assertions
```

Member order is the dependency order the members documented: shared setup →
Member 1 (Bronze) → Member 2 (identity) → Member 3 (survivorship) → Member 5
(this module) → Member 4 (analytics) → Member 6 (security).

### Three mistakes a naive "run every .sql in order" script makes

All three are handled by this harness, and each one produced a false failure the
first time it was written:

1. **Validation files assert immediately.** Every member's `*_validation_tests.sql`
   is a `DO` block, not a definition. Running it at load time fails because the
   pipeline has not run yet. They must run last.
2. **Some steps are already triggered.** Member 1's own scripts load the initial
   batches and call its incremental procedure. Calling
   `silver.process_incremental_batch('B1-CRM')` again raises an error on purpose,
   because that procedure only accepts `SIMULATED_CDC` batches.
3. **Not every routine is a silver procedure.** Member 4's loader is
   `gold.load_dim_customer()`, and Member 6's routines are trigger functions that
   fire on their own. Neither is something to `CALL` in the silver schema.

### Why some counts are asserted and others only measured

Counts this module owns are **asserted**, because a change there is a regression.
Counts belonging to another member's layer (Bronze, shared Silver tables,
`gold.dim_customer`) are **measured and printed**, because their values depend on
how much of that member's flow has run, and guessing them produces failures that
say nothing about this module.

This distinction came from experience: the first version of this harness asserted
guessed numbers for other members' tables and reported four failures that were
entirely the harness's fault.

### The check that found a real bug

Phase 5 re-measures this module's report **after** the other five members have
run, and compares it with the numbers from the single-module test. That
comparison is what caught a genuine defect: `08_validation_tests.sql` asserted
that every exception row had a *null* `customer_key`, which is only true in
isolation. Once Member 4 populated `gold.dim_customer`, the rows correctly gained
a key and the assertion failed.

The assertion was wrong, not the code. It now asserts what the assignment
actually requires — that the report holds the same number of rows as the fact
table, so no exception is dropped — which holds in both environments.

---

## 3. Static checks (no execution)

```bash
python validate_syntax.py       # parses all module scripts with pglast
python analyse.py               # dangling calls, dead objects, is each view used
python audit_comments.py        # comment share per file, comments missing Chinese
```

`validate_syntax.py` is worth running first because it is fast and catches syntax
errors before a slower execution run. It cannot see inside a plpgsql body, which
is exactly why the execution tests exist.

---

## 4. What is still not covered

| Gap | Why it matters | How to close it |
|---|---|---|
| Only one database engine version | PGlite tracks recent PostgreSQL; the marker uses PostgreSQL 15 | Run both suites once on the marker's PostgreSQL before submission |
| Members' own tests are not compared against each other's expected values | Member 1's test asserts 34 Bronze customer rows; the integration run holds 13, because only part of its flow runs in this harness | Ask each member to run `integration.mjs` and confirm their own module still meets its own numbers |
| Member 3's README notes it was developed against a corrected copy of Member 2 | A local fix in one module is invisible to the others | Whoever owns Member 2 should confirm the correction is in the committed version |
| Concurrency and volume | Everything here is single-session and small | Out of scope for the prototype |

## References

ElectricSQL 2025, *PGlite: PostgreSQL in WebAssembly*, viewed 14 October 2026,
<https://electric-sql.com/primitives/pglite>.

Darafei Praliaskouski 2024, *pglast: PostgreSQL Languages AST and statements
prettifier*, version 7, viewed 14 October 2026, <https://pglast.readthedocs.io/>.
