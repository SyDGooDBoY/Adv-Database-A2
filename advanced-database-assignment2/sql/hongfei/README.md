# Member 1 — Incremental Loading and CDC

This folder contains the Source-to-Bronze part of the project. It loads the
sample data, keeps the raw records in Bronze, and processes the second batch as
simulated CDC.

The main idea is simple: raw data is kept even when a batch fails, but the
watermark only moves forward after the batch has passed validation.

## Before running these scripts

Run the shared setup scripts in `../00_shared_setup/` from `00` to `49` first.
They create the Source, Bronze and Silver tables used here.

The sample CSV data has already been converted into `INSERT` statements in
`02_seed_source_data.sql`, so the scripts can be run directly in CloudBeaver.
There is no need to configure a server-side CSV path.

## Run order

Run the files in this order:

1. `01_add_incremental_controls.sql`
2. `02_seed_source_data.sql`
3. `03_load_initial_bronze.sql`
4. `04_create_incremental_procedure.sql`
5. `05_run_failure_retry_demo.sql`
6. `06_run_remaining_incremental_batches.sql`
7. `07_validation_tests.sql`

The first four files set everything up. Files `05` and `06` run the demo
batches, and file `07` checks the final result.

## What the scripts do

`01_add_incremental_controls.sql` adds the batch constraints, supporting
indexes and the latest-successful-watermark view.

`02_seed_source_data.sql` loads the supplied sample data into the simulated
operational source tables. The writes are idempotent, so rerunning the file does
not create duplicate source records.

`03_load_initial_bronze.sql` loads the three B1 batches into Bronze and checks
that their row counts match the batch control records. Once they pass, the
initial batches are published to Silver as successful.

`04_create_incremental_procedure.sql` creates the reusable CDC procedure. For
each B2 batch, it:

- stages the raw rows and CDC events in Bronze;
- checks row counts, operation types, source IDs, payload references and event
  sequences;
- publishes valid CDC events to Silver;
- advances the watermark only when validation succeeds;
- records a blocking data-quality issue when the batch fails.

`05_run_failure_retry_demo.sql` deliberately fails `B2-CRM` after its Bronze
rows have been staged. It then retries the same batch successfully and runs it
once more to show that the procedure is safe to rerun.

`06_run_remaining_incremental_batches.sql` processes the Lending and AML/KYC
batches. Lending succeeds. AML/KYC fails because the supplied `CDC-019` event
has a blank `operation_type`. That bad value is kept as supplied instead of
being silently changed.

`07_validation_tests.sql` checks the batch states, row counts, watermarks,
retained raw events and recorded quality issues.

## Source-to-Bronze mapping

| Source | Source table | Bronze table | Record key |
|---|---|---|---|
| CRM | `source_systems.raw_crm_customer` | `bronze.raw_crm_customer` | customer reference + version |
| CRM | `source_systems.raw_banking_account_snapshot` | `bronze.raw_banking_account_snapshot` | account reference + version |
| CRM | `source_systems.raw_account_transaction` | `bronze.raw_account_transaction` | transaction reference |
| Lending | `source_systems.raw_lending_customer` | `bronze.raw_lending_customer` | customer reference + version |
| Lending | `source_systems.raw_loan_snapshot` | `bronze.raw_loan_snapshot` | loan reference + version |
| AML/KYC | `source_systems.raw_aml_kyc_customer` | `bronze.raw_aml_kyc_customer` | customer reference + version |
| AML/KYC | `source_systems.raw_kyc_verification` | `bronze.raw_kyc_verification` | KYC reference |
| AML/KYC | `source_systems.raw_aml_screening` | `bronze.raw_aml_screening` | screening reference |

The source-system, batch and CDC control tables are also copied into Bronze.
Validated control records are then published to Silver for downstream modules.

## Expected demo result

The three initial batches should succeed:

- `B1-CRM`: 34 records
- `B1-LEND`: 12 records
- `B1-AMLKYC`: 27 records

After the incremental demo:

- `B2-CRM` succeeds after the forced failure and retry;
- `B2-LEND` succeeds normally;
- `B2-AMLKYC` remains failed because of `CDC-019`;
- CRM and Lending watermarks move to `2026-09-15`;
- the AML/KYC watermark stays at `2026-09-01`.

## Rerunning the demo

Bronze inserts use conflict handling, so existing raw rows are not duplicated.
A batch already marked `SUCCEEDED` is skipped. A failed batch can be retried,
and its watermark remains unchanged until that retry succeeds.

This folder stops at reliable Bronze data and validated Silver control records.
Customer matching and golden-record processing are handled by the downstream
modules.
