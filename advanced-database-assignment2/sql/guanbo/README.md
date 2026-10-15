# Member 5 - KYC/AML Exceptions and Reporting

This module implements the report's Member 5 scope in PostgreSQL:

- validation rules over KYC verification and AML screening events;
- case-status processing for verification and AML investigations;
- exception reporting through the `FACT_COMPLIANCE_EXCEPTION` accumulating
  snapshot fact and its reporting views.

## Prerequisite

Run every script in `../00_shared_setup/` from `00` through `49` before this
module; they create the Source, Bronze, Silver and Gold tables used here.

Member 1's scripts (`../hongfei/01`-`03`) populate `bronze` and
`silver.ingestion_batch` / `silver.source_system`. This module reads its source
rows from Bronze and reuses the existing Silver batch and source-system control
rows when they are already present. Neither is required for the module to run:
a failed upstream batch still leaves its raw rows in Bronze, and this module
processes them from there.

Member 2's `silver.customer_master` and `silver.source_customer_record` rows are
used when available. `02_load_kyc_aml_dimensions.sql` creates the minimal
customer identity that this module's own events reference, so the module can be
demonstrated before identity resolution is complete.

## Run order

1. `00_add_compliance_constraints.sql`
2. `01_seed_kyc_aml_bronze.sql`
3. `02_load_kyc_aml_dimensions.sql`
4. `03_create_kyc_aml_load_procedures.sql`
5. `04_create_kyc_aml_validation.sql`
6. `05_create_case_processing.sql`
7. `06_create_exception_fact.sql`
8. `07_create_compliance_reporting_views.sql`
9. `08_validation_tests.sql`
10. `09_add_object_descriptions.sql`

`09` attaches a description to every table, column, view, function and procedure
this module owns, so the structure is readable in CloudBeaver without opening the
scripts. It is idempotent and describes only this module's own objects, so no other
member's descriptions are touched. `TABLE_COMMENTS.md` in this directory covers the
same ground in prose, table by table and column by column; it is reference
documentation and is not executed.

Then execute one call per batch:

```sql
CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');
CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');
CALL silver.publish_compliance_cases(DATE '2026-09-30');
CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');
```

`B2-AMLKYC` is the batch that Member 1 deliberately leaves `FAILED` because
supplied event `CDC-019` carries a blank `operation_type`. Its raw AML/KYC rows
are still present in Bronze, so the compliance exception of `2026-09-15`
(`SCR-005-2`, a watchlist potential match) is processed and reported here rather
than being lost with the failed load.

## Layer ownership

- `bronze.raw_kyc_verification`, `bronze.raw_aml_screening`: read-only input to
  this module. `01_seed_kyc_aml_bronze.sql` loads them only when they are empty,
  so it never disturbs Member 1's Bronze retention.
- `silver.kyc_verification_record`, `silver.special_verification_case`,
  `silver.aml_screening_result`, `silver.aml_case`: published and owned by this
  module.
- `silver.data_quality_issue`, `silver.data_lineage_record`: written by this
  module for the records it validates.
- `gold.fact_compliance_exception`: published and owned by this module.

## Validation rules

Reportable findings create or reuse a `special_verification_case` with
`case_type` in `KYC_GAP`, `IDENTITY_MISMATCH` and `STATUS_DISCREPANCY`, as the
report requires. Repeated findings for the same customer and issue type reuse
the existing open case instead of opening a new one. Other validation failures
remain quality records without a case.

The two detection functions implement **18 rules**: 8 over KYC verification
events and 10 over AML screening events.

### KYC verification rules (8)

| Rule | Finding | Case type | Severity |
|---|---|---|---|
| `KYC_EVENT_SUBJECT_REQUIRED` | no customer and no source customer record | — | BLOCKING |
| `KYC_IDENTITY_LINK_MISMATCH` | customer and source record not the same identity | `IDENTITY_MISMATCH` | HIGH |
| `KYC_VERIFICATION_TYPE_INVALID` | unknown verification type | — | MEDIUM |
| `KYC_VERIFICATION_STATUS_INVALID` | unknown verification status | — | MEDIUM |
| `KYC_VERIFICATION_EXPIRED` | the check has lapsed at the reference date | `STATUS_DISCREPANCY` | HIGH |
| `KYC_VERIFICATION_STATUS_DISCREPANCY` | successful check that cannot be relied on as recorded | `STATUS_DISCREPANCY` | HIGH |
| `KYC_VERIFICATION_INCOMPLETE` | the check did not complete (pending, missing document, failed) | `KYC_GAP` | MEDIUM |
| `KYC_VERIFICATION_UNRESOLVED_IDENTITY` | event not yet linked to a golden customer | — | LOW |

### AML screening rules (10)

| Rule | Finding | Case type | Severity |
|---|---|---|---|
| `AML_EVENT_SUBJECT_REQUIRED` | no customer and no source customer record | — | BLOCKING |
| `AML_IDENTITY_LINK_MISMATCH` | customer and source record not the same identity | `IDENTITY_MISMATCH` | HIGH |
| `AML_SCREENING_TYPE_INVALID` | unknown screening type | — | MEDIUM |
| `AML_SCREENING_RESULT_INVALID` | unknown screening result | — | MEDIUM |
| `AML_REVIEW_FLAG_INCONSISTENT` | alert raised while review is not required | `STATUS_DISCREPANCY` | HIGH |
| `AML_REVIEW_REQUIRED` | an alert that requires investigation | `AML_SCREENING_REVIEW` | MEDIUM |
| `AML_CLEAR_SCREENING_WITH_REVIEW` | clear result flagged for review | `STATUS_DISCREPANCY` | MEDIUM |
| `AML_CLEAR_SCREENING_SCORE_INCONSISTENT` | clear result carrying an alert-level score | `STATUS_DISCREPANCY` | MEDIUM |
| `AML_MATCH_SCORE_OUT_OF_RANGE` | score outside 0.0000-1.0000 | — | MEDIUM |
| `AML_MATCH_SCORE_MISSING` | alert raised without a match score | — | MEDIUM |
BLOCKING findings prevent the affected event from being published to Silver.
Every other finding is REPORTABLE: the event is published, the quality issue is
retained, and a case is opened or reused when the rule maps to a case type. A
rule with no case type stays a quality record: the LOW unresolved-identity
notice is recorded because an identity that is still pending is a fact the
report should show, but it is not itself a compliance exception.

## Case-state rules

The rules that govern a stored case rather than an incoming event are enforced
by CHECK constraints in `00_add_compliance_constraints.sql`, so an invalid case
cannot be written by any code path:

| Constraint | Enforces |
|---|---|
| `ck_special_verification_case_subject` | at least one subject or trigger reference, excluding the assignee |
| `ck_special_verification_case_type` | `KYC_GAP`, `IDENTITY_MISMATCH` or `STATUS_DISCREPANCY` |
| `ck_special_verification_case_status` | `OPEN`, `IN_REVIEW`, `RESOLVED` or `CLOSED` |
| `ck_special_verification_case_resolution` | `RESOLVED` requires `resolved_at`; an active case must not carry one |
| `ck_aml_case_subject_or_trigger` | a customer, source record, screening reference or documented trigger |
| `ck_aml_case_lifecycle` | `CLOSED` agrees with `closed_at`, and an open case has none |
| `ck_fact_compliance_exception_single_case` | exactly one case reference, agreeing with `exception_source_type` |

## Exception reporting

`gold.fact_compliance_exception` holds one accumulating row per originating
case. Exactly one of `verification_case_id` and `aml_case_id` is populated and
it must agree with `exception_source_type`. `customer_key` stays null while the
identity is unresolved and is filled in once `gold.dim_customer` has a current
version for that customer. `days_open` counts calendar days from `opened_date`
to `resolved_date`, or to `as_of_date` while the case is open, and is capped at
the as-of date so an exception is never reported as older than the reporting
period. Refreshing a case updates the same row.

## Expected demonstration

`08_validation_tests.sql` asserts these figures. With the supplied synthetic
data at reference date `2026-09-30`:

| Result | Count |
|---|---|
| KYC verification events published to Silver | 9 |
| AML screening events published to Silver | 10 |
| Validation issues registered | 3 |
| Verification cases | 2 |
| AML cases | 1 |
| Compliance exception fact rows | 3 |

| Rule | Event | Case | Severity |
|---|---|---|---|
| `KYC_VERIFICATION_INCOMPLETE` | `VFY-004`, Noah Chen, missing document | `KYC_GAP` | MEDIUM |
| `KYC_VERIFICATION_EXPIRED` | `VFY-012`, Leo Martin, lapsed `2026-08-15` | `STATUS_DISCREPANCY` | HIGH |
| `AML_REVIEW_REQUIRED` | `SCR-005-2`, Olivia Brooks, watchlist match `0.9200` | `AML_SCREENING_REVIEW` | MEDIUM |

`silver.customer_kyc_status(DATE '2026-09-30')` then reports 7 customers
`VERIFIED` and 2 `REVIEW_REQUIRED`, which is the report's rule applied to the
same data: a customer with an unresolved exception is never `VERIFIED`.

Rerunning every script and every procedure changes no row counts, because every
write is keyed on a deterministic identifier.

## Verification performed

The module was executed against a real PostgreSQL build, not only parsed:

- `validate_syntax.py` parses all nine files with `pglast`, the PostgreSQL
  parser, including a combined single pass over the whole module.
- `verification/member5-kyc-aml/verify.mjs` at the repository root runs the
  shared setup, this module, the pipeline calls and `08_validation_tests.sql`
  against PGlite, a PostgreSQL build compiled to WebAssembly, then asserts the
  resulting row counts and prints the reports. Run `pnpm install` in that
  directory once, then `node verify.mjs`.

Both checks were used to find and correct defects that a syntax check cannot
see, including a plpgsql alias referenced within its own select list, a
`PERFORM` used to call a procedure, the two shared
`fact_compliance_exception` unique indexes rejecting every row after the first
because PostgreSQL treats nulls as distinct in a unique index, and an expiry
rule that could not fire for a record already flagged `EXPIRED`.
