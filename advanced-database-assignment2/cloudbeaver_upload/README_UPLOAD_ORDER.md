# CloudBeaver upload bundle

These files are generated from the project SQL in dependency order for PostgreSQL 15+.

## If you already ran the previous deployment

Do **not** rerun `01_full_deployment.sql` on the populated database.

1. Keep using the same CloudBeaver PostgreSQL connection and database.
2. Upload `04_update_existing_database_member4_07.sql`.
3. Open it in the SQL Editor and execute the **entire file** with **Alt+X**.
4. Confirm that the final report queries return both `2026-09-01` and `2026-09-15`.
5. Upload the regenerated `02_validation.sql`, execute the entire file with **Alt+X**, and confirm the Member 4 checks show `PASS`.
6. Restart or refresh the Python dashboard. Its date selector should now contain two reporting dates and its trend charts should become line charts.

The update is implemented as one atomic PostgreSQL `DO` statement. It replaces only Member 4 financial, risk-assessment and customer-snapshot data. It does not rebuild Bronze ingestion, identity resolution, KYC/AML cases or security roles. PostgreSQL commits the whole statement when it succeeds and automatically rolls it back if it fails, so the file does not leave an open `BEGIN` transaction.

## If you are deploying into a new empty database

1. Upload `01_full_deployment.sql` and execute the entire file with **Alt+X**.
2. Optionally upload `03_security_roles_admin.sql` and execute it only if an administrator has approved the access matrix and your account can create roles.
3. Upload `02_validation.sql` and execute the entire file with **Alt+X**.

The regenerated full deployment creates Member 4 objects first, loads Member 5 KYC/AML data next, and only then publishes the two Member 4 snapshots. This order is required for the snapshot risk ratings to use the loaded compliance results.

## Important notes

- Stop if CloudBeaver reports a red error; use the nearest `BEGIN SOURCE FILE` comment to identify the original file.
- `B2-AMLKYC` ending in `FAILED` is an intentional test outcome caused by supplied event `CDC-019` having a blank operation type.
- `02_validation.sql` ends with Member 6's transactional demo, which deliberately rolls its test changes back. Run the whole validation file in one SQL Editor session.
- The original CSV files do not need to be imported separately because the deployment SQL contains the required synthetic seed inserts.
- Never run `01_full_deployment.sql` against the already populated database; use file `04` for this Member 4 update.
