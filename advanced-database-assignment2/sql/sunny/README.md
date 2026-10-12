# Member 6: Security, Audit and Data Quality Monitoring

This folder is designed for the current `Sunny` branch of the group project.
It uses the four existing PostgreSQL schemas (`source_systems`, `bronze`,
`silver`, `gold`) and does not change the shared table definitions or Member 1's
incremental load procedure.

## What this module does

| File | Purpose | Execution |
|---|---|---|
| `01_quality_findings.sql` | Read-only view of structural rule failures across Bronze, Silver and Gold | Table owner/developer |
| `02_record_quality_issues.sql` | Idempotent function to record non-CDC failures in `silver.data_quality_issue` | Table owner/developer |
| `03_security_roles.sql` | Five PostgreSQL NOLOGIN group roles and example GRANT/REVOKE policy | **Administrator or role/table owner only** |
| `04_audit_quality_changes.sql` | Trigger that records successful changes to `silver.data_quality_issue` in `silver.access_audit_log`; protects log rows from UPDATE/DELETE | Table owner/developer |
| `05_validation_demo.sql` | Transactional test with an intentionally bad raw record, issue creation, rerun check and audit evidence | Developer, after 01/02/04 |

Run the shared schema scripts `00`–`49` first. Run Member 1's scripts
`01`–`06` for meaningful Bronze data, including the intentionally invalid
`CDC-019` event. Then run this module's `01`, `02`, `04` and `05` in order.
Run `03` separately only after the team approves the access matrix and an
administrator confirms role-creation privileges. `05` rolls back its synthetic
test row, issue and audit event; run it in one CloudBeaver editor session.

## Rule ownership and expected findings

- `CDC-019` has a blank operation type. `01` shows it as a read-only finding.
  Member 1 already records a batch-level `incremental_batch_validation` issue
  for `B2-AMLKYC`, so `02` skips Member 6 CDC findings to avoid duplicate issue
  rows for the same load failure.
- `VFY-004` (missing document) and `VFY-012` (expired status) appear as
  read-only findings after initial KYC data is loaded. `02` excludes them until
  Member 5 creates the required verification cases.
- `02` records blank source references, wrong raw-table sources, raw batch/source
  mismatches, duplicate current Silver identities or attribute selections,
  and Gold relationship failures. It never changes Bronze values.
- A `BLOCKING` finding is an output for the pipeline owner to enforce before
  publication. This monitoring module does not itself stop Member 1's or the
  Gold module's procedures.
- A rule's absence from the result means no **observed** failure in the loaded
  rows. If tables are empty, it does not prove the pipeline works. Confirm row
  counts and Member 1's run status before taking screenshots.
- KYC gaps, identity disagreements and AML alerts are owned jointly with
  Members 2 and 5. Do not insert a reportable KYC or identity issue into
  `silver.data_quality_issue` until its `verification_case_id` exists; the
  current logical model requires that link. Member 6 can add those checks after
  the case workflow is available.

Use a distinct validation run ID for each actual execution, for example:

```sql
SELECT silver.member6_sync_quality_issues('M6-2026-10-12-01');
SELECT * FROM silver.data_quality_issue
WHERE validation_run_id = 'M6-2026-10-12-01';
```

The same run ID can be retried without creating duplicate issues. A new run ID
creates a new observation. Resolution is a reviewed business decision: re-run
the check and update the issue status only after the underlying problem is
fixed; this module does not auto-close earlier evidence.

## Proposed access matrix

| Database group role | Intended access |
|---|---|
| `m6_pipeline` | Read/write source tables; append/read Bronze; maintain Silver ingestion-control rows and load quality issues. |
| `m6_steward` | Read customer reconciliation and quality results; record/review quality issues. |
| `m6_analyst` | Read Gold customer dimension and snapshots only. |
| `m6_compliance` | Read relevant Silver KYC/AML cases, Gold compliance exceptions and limited quality evidence. |
| `m6_auditor` | Read audit, quality and ingestion-control evidence only. |

`silver.role` is the **application role catalogue**. PostgreSQL `m6_*` roles
are separate database principals. This module creates no login or password and
assigns no teammate to a role. Existing grants to `PUBLIC`, table owners or
other inherited roles can still widen effective access; the administrator
must inspect them before claiming access isolation. New tables and views
created later need a separate grant review.

## Audit scope and evidence

The trigger in `04` records committed INSERT/UPDATE/DELETE operations on
`silver.data_quality_issue`. It captures the database login, action, target
record, time and client address when available. It does **not** capture SELECT,
failed statements or rolled-back transactions. Database-wide query access
logging requires server-side PostgreSQL logging or another approved audit
facility configured by the database administrator. `silver.access_audit_log`
alone is not evidence that all CloudBeaver queries have been logged.
If CloudBeaver uses one shared PostgreSQL login, the recorded actor is that
shared login; distinct users require distinct database logins or an additional
trusted application-level identity supplied by the connection layer.

For the report, capture: Member 1 batch status and `CDC-019`; Member 6 finding
view; the transactional test output; audit event inside the test transaction;
and the effective role-privilege query at the end of `05` after admin setup.
