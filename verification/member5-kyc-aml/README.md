# Member 5 verification harness

This directory holds the executable checks used while building the Member 5
KYC/AML module at `advanced-database-assignment2/sql/guanbo/`. It is separate
from `sql/` so the assignment deliverable stays limited to database scripts.

No PostgreSQL server is required: PGlite is a real PostgreSQL build compiled to
WebAssembly, so the checks exercise actual server behaviour, including plpgsql
bodies, constraints, indexes and upserts.

## Usage

```bash
pnpm install
node verify.mjs    # shared setup + module + pipeline + 08 assertions + reports
node figures.mjs   # the demonstration figures quoted in the module README
node gate.mjs      # encoding and PostgreSQL-parser checks only
```

`verify.mjs` and `figures.mjs` are pure Node. `gate.mjs` shells out to
`validate_syntax.py`, so it needs `DSH_PYTHON` set to a Python interpreter with
`pglast` installed.

## What each check covers

| Script | Purpose |
|---|---|
| `verify.mjs` | Runs `00_shared_setup`, the nine Member 5 scripts, the four pipeline calls and the acceptance tests, then asserts the resulting row counts and prints every report |
| `figures.mjs` | Prints the counts, findings, cases, exception report and KYC status from a clean run |
| `gate.mjs` | Fails on a UTF-8 BOM, which PostgreSQL rejects, and parses every module file with pglast |

`gate.mjs` calls `../advanced-database-assignment2/sql/guanbo/validate_syntax.py`,
which is kept with the module because it validates that module's scripts.
