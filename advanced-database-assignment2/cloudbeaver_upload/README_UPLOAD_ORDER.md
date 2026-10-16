# CloudBeaver upload bundle

These files are generated from the project SQL in dependency order for PostgreSQL 15+.

## Upload and execution order

1. Connect CloudBeaver to a **new, empty PostgreSQL database**.
2. Upload `01_full_deployment.sql` and execute the entire file with **Alt+X**.
3. Optionally upload `03_security_roles_admin.sql` and execute it only if an administrator has approved the access matrix and your account can create roles.
4. Upload `02_validation.sql` and execute the entire file with **Alt+X**.

## Important notes

- Stop if CloudBeaver reports a red error; use the nearest `BEGIN SOURCE FILE` comment to identify the original file.
- `B2-AMLKYC` ending in `FAILED` is an intentional test outcome caused by supplied event `CDC-019` having a blank operation type.
- `02_validation.sql` ends with Member 6's transactional demo, which deliberately rolls its test changes back. Run the whole validation file in one SQL Editor session.
- The original CSV files do not need to be imported separately because the deployment SQL contains the required seed inserts.
- Do not rerun the full deployment against a partially populated database. Create a clean database or resolve the first error before retrying.
