# Member 1 - Incremental Synchronisation and Load Control

This module implements the report's Member 1 scope in PostgreSQL:

- source-to-Bronze mapping and initial loading;
- ingestion-batch status and record-count control;
- simulated CDC for inserts, updates and deletes;
- append-only Bronze retention;
- successful-only watermark advancement;
- idempotent reruns, failure logging and retry;
- validation queries suitable for report screenshots.

## Prerequisite

Run every script in `../00_shared_setup/` from `00` through `49` before this
module. The shared scripts create the Source, Bronze and Silver control tables
used here.

## Run order

1. `01_add_incremental_controls.sql`
2. `02_seed_source_data.sql`
3. `03_load_initial_bronze.sql`
4. `04_create_incremental_procedure.sql`
5. `05_run_failure_retry_demo.sql`
6. `06_run_remaining_incremental_batches.sql`
7. `07_validation_tests.sql`

`02_seed_source_data.sql` contains PostgreSQL `INSERT` statements generated
from the supplied CSV files. This makes the prototype runnable in CloudBeaver
without requiring PostgreSQL server access to a local Windows CSV path.

## Layer ownership

- `source_systems`: simulated operational input, including the supplied batch
  specifications and CDC events.
- `bronze`: append-only raw landing records. Delete operations are retained as
  `operation_type = 'D'`; no historical row is physically deleted.
- `silver.source_system`, `silver.ingestion_batch` and
  `silver.cdc_change_event`: authoritative integration-control records used by
  downstream modules.

Member 1 stops after producing reliable Bronze data and processable Silver CDC
events. Customer standardisation and identity matching are downstream work.

## Source-to-Bronze mapping

| Source | Source table | Bronze table | Business/change key |
|---|---|---|---|
| CRM | `source_systems.raw_crm_customer` | `bronze.raw_crm_customer` | source + customer reference + version |
| CRM | `source_systems.raw_banking_account_snapshot` | `bronze.raw_banking_account_snapshot` | source + account reference + version |
| CRM | `source_systems.raw_account_transaction` | `bronze.raw_account_transaction` | source + transaction reference |
| Lending | `source_systems.raw_lending_customer` | `bronze.raw_lending_customer` | source + customer reference + version |
| Lending | `source_systems.raw_loan_snapshot` | `bronze.raw_loan_snapshot` | source + loan reference + version |
| AML/KYC | `source_systems.raw_aml_kyc_customer` | `bronze.raw_aml_kyc_customer` | source + customer reference + version |
| AML/KYC | `source_systems.raw_kyc_verification` | `bronze.raw_kyc_verification` | source + KYC reference |
| AML/KYC | `source_systems.raw_aml_screening` | `bronze.raw_aml_screening` | source + screening reference |

The metadata tables `source_system`, `ingestion_batch` and
`cdc_change_event` are also copied to Bronze. Their validated, authoritative
versions are published in the Silver schema.

## Expected demonstration

- Initial B1 batches succeed: CRM 34 rows, Lending 12 rows and AML/KYC 27 rows.
- `B2-CRM` is deliberately failed once, leaving its watermark unchanged, then
  retried successfully without duplicate Bronze rows.
- `B2-LEND` succeeds normally.
- `B2-AMLKYC` fails validation because supplied event `CDC-019` has a blank
  `operation_type`. The invalid raw event remains in Bronze and a blocking data
  quality issue is retained. This is intentional evidence of error handling;
  do not silently convert the blank value to `I`.

After the demo, CRM and Lending advance from watermark `2026-09-01` to
`2026-09-15`. AML/KYC remains at `2026-09-01` because its incremental batch
failed.

## Rerun behaviour

Source and Bronze inserts use primary-key conflict handling. A batch already
marked `SUCCEEDED` is skipped, while a `FAILED` batch may be retried. Watermarks
are read only from successful batches and are never advanced by a failure.
