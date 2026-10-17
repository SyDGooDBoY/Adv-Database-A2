-- =============================================================================
-- CloudBeaver bundle 03: optional administrator security roles
-- Target: PostgreSQL 15+ through CloudBeaver
-- Optional: run only with administrator approval and CREATE ROLE/table-owner privileges.
-- Upload this file to the SQL Editor and execute the whole script with Alt+X.
-- Source-file boundary comments are retained for error tracing.
-- =============================================================================

-- >>> BEGIN SOURCE FILE: sql/module6_sunny/03_security_roles.sql

-- Member 6: prototype least-privilege database roles for PostgreSQL 15+.
-- ADMIN-ONLY: run as an owner/administrator after all shared tables exist.
-- These NOLOGIN group roles do not change any teammate's login until an
-- administrator explicitly grants role membership. Review the matrix in README.

DO $member6_roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'm6_pipeline') THEN
    CREATE ROLE m6_pipeline NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'm6_steward') THEN
    CREATE ROLE m6_steward NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'm6_analyst') THEN
    CREATE ROLE m6_analyst NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'm6_compliance') THEN
    CREATE ROLE m6_compliance NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'm6_auditor') THEN
    CREATE ROLE m6_auditor NOLOGIN;
  END IF;
END;
$member6_roles$;

-- The logical application role catalogue is separate from PostgreSQL roles.
INSERT INTO silver.role (role_id, role_name, role_description)
VALUES
  ('M6-PIPELINE', 'm6_pipeline', 'Ingestion and CDC processing'),
  ('M6-STEWARD', 'm6_steward', 'Customer quality review'),
  ('M6-ANALYST', 'm6_analyst', 'Curated customer analytics'),
  ('M6-COMPLIANCE', 'm6_compliance', 'KYC and AML case review'),
  ('M6-AUDITOR', 'm6_auditor', 'Read-only governance evidence')
ON CONFLICT DO NOTHING;

GRANT USAGE ON SCHEMA source_systems, bronze, silver TO m6_pipeline;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA source_systems
  TO m6_pipeline;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA bronze TO m6_pipeline;
GRANT SELECT, INSERT, UPDATE ON
  silver.source_system, silver.ingestion_batch,
  silver.cdc_change_event, silver.data_quality_issue
  TO m6_pipeline;
GRANT SELECT ON silver.vw_latest_successful_watermark TO m6_pipeline;
GRANT EXECUTE ON PROCEDURE silver.process_incremental_batch(varchar, boolean)
  TO m6_pipeline;

GRANT USAGE ON SCHEMA silver TO m6_steward;
GRANT SELECT ON
  silver.source_system, silver.ingestion_batch,
  silver.source_customer_record, silver.customer_master,
  silver.customer_source_match, silver.customer_attribute_source,
  silver.data_quality_issue, silver.vw_member6_quality_findings
  TO m6_steward;
GRANT INSERT, UPDATE ON silver.data_quality_issue TO m6_steward;
REVOKE ALL ON FUNCTION silver.member6_sync_quality_issues(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION silver.member6_sync_quality_issues(text)
  TO m6_steward;

-- Read-only consumption roles; no direct Bronze/raw KYC access for analysts.
GRANT USAGE ON SCHEMA gold TO m6_analyst;
GRANT SELECT ON gold.dim_customer, gold.fact_customer_snapshot
  TO m6_analyst;

GRANT USAGE ON SCHEMA silver, gold TO m6_compliance;
GRANT SELECT ON
  silver.kyc_verification_record, silver.special_verification_case,
  silver.aml_screening_result, silver.aml_case,
  silver.data_quality_issue, gold.fact_compliance_exception,
  gold.dim_customer
  TO m6_compliance;

GRANT USAGE ON SCHEMA silver TO m6_auditor;
GRANT SELECT ON
  silver.access_audit_log, silver.data_quality_issue,
  silver.ingestion_batch, silver.cdc_change_event
  TO m6_auditor;

-- Explicitly remove any earlier direct grants on sensitive raw tables from
-- the read-only personas. Inherited/PUBLIC privileges require separate review.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA source_systems, bronze
  FROM m6_analyst, m6_compliance, m6_auditor;
REVOKE ALL PRIVILEGES ON SCHEMA source_systems, bronze
  FROM m6_analyst, m6_compliance, m6_auditor;

-- No real login accounts are assigned here. The administrator can later run:
-- GRANT m6_analyst TO some_existing_login;
-- The database owner must review PUBLIC grants and other role memberships;
-- REVOKE above cannot remove privileges inherited by those routes.

-- <<< END SOURCE FILE: sql/module6_sunny/03_security_roles.sql
