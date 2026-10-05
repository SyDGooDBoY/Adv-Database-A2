-- PostgreSQL 15+
-- Silver - KYC and Verification
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.kyc_verification_record (
  kyc_verification_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50),
  source_customer_record_id varchar(50),
  source_system_id varchar(50) NOT NULL,
  reviewed_by varchar(50),
  source_kyc_reference varchar(100) NOT NULL,
  verification_type varchar(50) NOT NULL,
  verification_status varchar(30) NOT NULL,
  verification_date timestamp NOT NULL,
  expiry_date date,
  risk_level_at_verification varchar(30)
);

CREATE TABLE silver.special_verification_case (
  verification_case_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50),
  source_customer_record_id varchar(50),
  match_id varchar(50),
  kyc_verification_id varchar(50),
  assigned_user_id varchar(50),
  case_type varchar(50) NOT NULL,
  trigger_type varchar(50) NOT NULL,
  case_reason varchar(1000) NOT NULL,
  case_status varchar(30) NOT NULL,
  severity varchar(20) NOT NULL,
  opened_at timestamp NOT NULL,
  resolved_at timestamp,
  resolution_outcome varchar(1000)
);

CREATE UNIQUE INDEX kyc_verification_record_index_7 ON silver.kyc_verification_record (source_system_id, source_kyc_reference);

COMMENT ON TABLE silver.kyc_verification_record IS 'One verification event, unique by source + KYC reference. Require a customer or source customer record; both must agree if supplied. Keep earlier outcomes. reviewed_by is optional.';

COMMENT ON TABLE silver.special_verification_case IS 'One identity, matching or KYC case. At least one subject/trigger FK is required, excluding the assignee. All supplied links must agree. Identity can remain unresolved; RESOLVED requires resolved_at.';
