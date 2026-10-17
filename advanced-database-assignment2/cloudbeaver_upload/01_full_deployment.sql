-- =============================================================================
-- CloudBeaver bundle 01: full deployment
-- Target: PostgreSQL 15+ through CloudBeaver
-- Creates schemas and objects, loads supplied synthetic data, runs Member 5,
-- then publishes Member 4 snapshots for 2026-09-01 and 2026-09-15.
-- Upload this file to the SQL Editor and execute the whole script with Alt+X.
-- Use only for a new, empty database.
-- Source-file boundary comments are retained for error tracing.
-- =============================================================================

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/00_create_schemas.sql

-- PostgreSQL 15+
-- Physical layers defined by the report's Medallion Architecture.

CREATE SCHEMA IF NOT EXISTS source_systems;
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- <<< END SOURCE FILE: sql/00_shared_setup/00_create_schemas.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/10_source_system_tables.sql

-- PostgreSQL 15+
-- Simulated operational tables aligned column-for-column with the supplied CSV
-- files. This allows the later load script to use COPY without reshaping data.
-- base_people.csv and expected_identity_map.csv remain validation fixtures.

CREATE TABLE source_systems.source_system (
  source_system_id varchar(50) PRIMARY KEY,
  system_name varchar(100) NOT NULL,
  system_type varchar(30) NOT NULL,
  system_description varchar(500),
  system_owner varchar(100),
  active_flag boolean NOT NULL,
  CONSTRAINT uq_source_system_name UNIQUE (system_name)
);

CREATE TABLE source_systems.ingestion_batch (
  batch_id varchar(50) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  load_type varchar(30) NOT NULL,
  started_at timestamp NOT NULL,
  completed_at timestamp,
  load_status varchar(30) NOT NULL,
  records_received integer NOT NULL,
  records_processed integer NOT NULL,
  watermark_start varchar(150),
  watermark_end varchar(150),
  CONSTRAINT fk_source_batch_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id)
);

CREATE TABLE source_systems.cdc_change_event (
  change_event_id varchar(50) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_entity_name varchar(100) NOT NULL,
  source_record_reference varchar(150) NOT NULL,
  source_version_reference varchar(150) NOT NULL,
  operation_type varchar(10) NOT NULL,
  event_sequence bigint NOT NULL,
  source_change_time timestamp NOT NULL,
  captured_at timestamp NOT NULL,
  change_payload text NOT NULL,
  CONSTRAINT uq_source_cdc_sequence
    UNIQUE (source_system_id, source_entity_name, event_sequence),
  CONSTRAINT fk_source_cdc_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_cdc_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_crm_customer (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  operation_type varchar(10) NOT NULL,
  source_full_name varchar(150),
  source_date_of_birth date,
  source_email_address varchar(150),
  source_phone_number varchar(50),
  source_address varchar(255),
  record_status varchar(30) NOT NULL,
  source_last_updated_at timestamp,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_crm_customer_version
    UNIQUE (source_system_id, source_customer_reference, source_record_version),
  CONSTRAINT fk_crm_customer_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_crm_customer_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_lending_customer (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  operation_type varchar(10) NOT NULL,
  source_full_name varchar(150),
  source_date_of_birth date,
  source_email_address varchar(150),
  source_phone_number varchar(50),
  source_address varchar(255),
  record_status varchar(30) NOT NULL,
  source_last_updated_at timestamp,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_lending_customer_version
    UNIQUE (source_system_id, source_customer_reference, source_record_version),
  CONSTRAINT fk_lending_customer_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_lending_customer_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_aml_kyc_customer (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  operation_type varchar(10) NOT NULL,
  source_full_name varchar(150),
  source_date_of_birth date,
  source_email_address varchar(150),
  source_phone_number varchar(50),
  source_address varchar(255),
  record_status varchar(30) NOT NULL,
  source_last_updated_at timestamp,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_aml_kyc_customer_version
    UNIQUE (source_system_id, source_customer_reference, source_record_version),
  CONSTRAINT fk_aml_kyc_customer_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_aml_kyc_customer_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_banking_account_snapshot (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_account_reference varchar(100) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  operation_type varchar(10) NOT NULL,
  account_type varchar(50) NOT NULL,
  account_status varchar(30) NOT NULL,
  currency_code varchar(3) NOT NULL,
  current_balance decimal(20,2) NOT NULL,
  opened_date date NOT NULL,
  closed_date date,
  as_of_date date NOT NULL,
  daily_income decimal(18,2),
  daily_cost decimal(18,2),
  credit_exposure decimal(18,2),
  source_last_updated_at timestamp NOT NULL,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_source_account_version
    UNIQUE (source_system_id, source_account_reference, source_record_version),
  CONSTRAINT fk_source_account_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_account_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_loan_snapshot (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_loan_reference varchar(100) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  operation_type varchar(10) NOT NULL,
  loan_type varchar(50) NOT NULL,
  loan_status varchar(30) NOT NULL,
  original_amount decimal(20,2) NOT NULL,
  outstanding_balance decimal(20,2) NOT NULL,
  interest_rate decimal(9,6) NOT NULL,
  start_date date NOT NULL,
  maturity_date date,
  as_of_date date NOT NULL,
  daily_income decimal(18,2),
  daily_cost decimal(18,2),
  credit_exposure decimal(18,2),
  source_last_updated_at timestamp NOT NULL,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_source_loan_version
    UNIQUE (source_system_id, source_loan_reference, source_record_version),
  CONSTRAINT fk_source_loan_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_loan_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_account_transaction (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_transaction_reference varchar(100) NOT NULL,
  source_account_reference varchar(100) NOT NULL,
  transaction_date timestamp NOT NULL,
  transaction_type varchar(50) NOT NULL,
  transaction_amount decimal(20,2) NOT NULL,
  transaction_status varchar(30) NOT NULL,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_source_transaction
    UNIQUE (source_system_id, source_transaction_reference),
  CONSTRAINT fk_source_transaction_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_transaction_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_kyc_verification (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_kyc_reference varchar(100) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  verification_type varchar(50) NOT NULL,
  verification_status varchar(30) NOT NULL,
  verification_date timestamp NOT NULL,
  expiry_date date,
  risk_level_at_verification varchar(30),
  reviewer_reference varchar(100),
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_source_kyc_verification
    UNIQUE (source_system_id, source_kyc_reference),
  CONSTRAINT fk_source_kyc_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_kyc_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

CREATE TABLE source_systems.raw_aml_screening (
  bronze_record_reference varchar(300) PRIMARY KEY,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_screening_reference varchar(100) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  screening_type varchar(50) NOT NULL,
  screening_date timestamp NOT NULL,
  screening_result varchar(50) NOT NULL,
  match_score decimal(5,4),
  provider_reference varchar(150),
  review_required_flag boolean NOT NULL,
  ingested_at timestamp NOT NULL,
  CONSTRAINT uq_source_aml_screening
    UNIQUE (source_system_id, source_screening_reference),
  CONSTRAINT fk_source_aml_screening_system
    FOREIGN KEY (source_system_id)
    REFERENCES source_systems.source_system (source_system_id),
  CONSTRAINT fk_source_aml_screening_batch
    FOREIGN KEY (batch_id)
    REFERENCES source_systems.ingestion_batch (batch_id)
);

-- <<< END SOURCE FILE: sql/00_shared_setup/10_source_system_tables.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/20_bronze_raw_tables.sql

-- PostgreSQL 15+
-- Immutable raw landing tables. LIKE ... INCLUDING ALL copies source column
-- definitions and indexes but not foreign keys, so malformed or orphaned raw
-- records can still be retained for investigation.

CREATE TABLE bronze.source_system
  (LIKE source_systems.source_system INCLUDING ALL);

CREATE TABLE bronze.ingestion_batch
  (LIKE source_systems.ingestion_batch INCLUDING ALL);

CREATE TABLE bronze.cdc_change_event
  (LIKE source_systems.cdc_change_event INCLUDING ALL);

CREATE TABLE bronze.raw_crm_customer
  (LIKE source_systems.raw_crm_customer INCLUDING ALL);

CREATE TABLE bronze.raw_lending_customer
  (LIKE source_systems.raw_lending_customer INCLUDING ALL);

CREATE TABLE bronze.raw_aml_kyc_customer
  (LIKE source_systems.raw_aml_kyc_customer INCLUDING ALL);

CREATE TABLE bronze.raw_banking_account_snapshot
  (LIKE source_systems.raw_banking_account_snapshot INCLUDING ALL);

CREATE TABLE bronze.raw_loan_snapshot
  (LIKE source_systems.raw_loan_snapshot INCLUDING ALL);

CREATE TABLE bronze.raw_account_transaction
  (LIKE source_systems.raw_account_transaction INCLUDING ALL);

CREATE TABLE bronze.raw_kyc_verification
  (LIKE source_systems.raw_kyc_verification INCLUDING ALL);

CREATE TABLE bronze.raw_aml_screening
  (LIKE source_systems.raw_aml_screening INCLUDING ALL);

-- <<< END SOURCE FILE: sql/00_shared_setup/20_bronze_raw_tables.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/30_silver_source_integration_control.sql

-- PostgreSQL 15+
-- Silver - Source and Integration Control
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.source_system (
  source_system_id varchar(50) PRIMARY KEY NOT NULL,
  system_name varchar(100) NOT NULL,
  system_type varchar(30) NOT NULL,
  system_description varchar(500),
  system_owner varchar(100),
  active_flag boolean NOT NULL
);

CREATE TABLE silver.ingestion_batch (
  batch_id varchar(50) PRIMARY KEY NOT NULL,
  source_system_id varchar(50) NOT NULL,
  load_type varchar(30) NOT NULL,
  started_at timestamp NOT NULL,
  completed_at timestamp,
  load_status varchar(30) NOT NULL,
  records_received integer NOT NULL,
  records_processed integer NOT NULL,
  watermark_start varchar(150),
  watermark_end varchar(150)
);

CREATE TABLE silver.cdc_change_event (
  change_event_id varchar(50) PRIMARY KEY NOT NULL,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_entity_name varchar(100) NOT NULL,
  source_record_reference varchar(150) NOT NULL,
  source_version_reference varchar(150) NOT NULL,
  operation_type varchar(10) NOT NULL,
  event_sequence bigint NOT NULL,
  source_change_time timestamp NOT NULL,
  captured_at timestamp NOT NULL,
  change_payload text NOT NULL
);

CREATE TABLE silver.data_quality_issue (
  data_quality_issue_id varchar(50) PRIMARY KEY NOT NULL,
  batch_id varchar(50),
  source_system_id varchar(50),
  verification_case_id varchar(50),
  validation_run_id varchar(100) NOT NULL,
  data_layer varchar(20) NOT NULL,
  entity_name varchar(100) NOT NULL,
  record_reference varchar(150) NOT NULL,
  record_version_reference varchar(150) NOT NULL,
  attribute_name varchar(100),
  rule_name varchar(100) NOT NULL,
  rule_version varchar(30) NOT NULL,
  issue_type varchar(50) NOT NULL,
  issue_description varchar(1000) NOT NULL,
  severity varchar(20) NOT NULL,
  detected_at timestamp NOT NULL,
  resolved_at timestamp,
  issue_status varchar(20) NOT NULL
);

CREATE TABLE silver.data_lineage_record (
  lineage_id varchar(50) PRIMARY KEY NOT NULL,
  batch_id varchar(50),
  source_system_id varchar(50),
  transformation_run_id varchar(100) NOT NULL,
  source_layer varchar(20) NOT NULL,
  source_entity_name varchar(100) NOT NULL,
  source_record_reference varchar(150) NOT NULL,
  source_version_reference varchar(150) NOT NULL,
  source_attribute_name varchar(100),
  source_record_snapshot text NOT NULL,
  target_layer varchar(20) NOT NULL,
  target_entity_name varchar(100) NOT NULL,
  target_record_reference varchar(150) NOT NULL,
  target_version_reference varchar(150) NOT NULL,
  target_attribute_name varchar(100),
  target_record_snapshot text NOT NULL,
  transformation_name varchar(150) NOT NULL,
  transformation_version varchar(30) NOT NULL,
  transformation_timestamp timestamp NOT NULL
);

CREATE UNIQUE INDEX source_system_index_0 ON silver.source_system (system_name);

CREATE UNIQUE INDEX cdc_change_event_index_1 ON silver.cdc_change_event (source_system_id, source_entity_name, event_sequence);

COMMENT ON TABLE silver.source_system IS 'One row per contributing operational source system. CRM Banking, Lending and AML/KYC have distinct source identifiers.';

COMMENT ON TABLE silver.ingestion_batch IS 'One row per ingestion run. The batch belongs to one source. Incremental watermarks advance only after successful processing.';

COMMENT ON TABLE silver.cdc_change_event IS 'One row per source change event. Source + entity + event sequence is unique across batches. Sequence values order events within that source entity stream; batch and event sources must agree. The prototype uses simulated CDC.';

COMMENT ON TABLE silver.data_quality_issue IS 'One rule failure for one record version in a validation run. Blocking issues prevent publication. Reportable KYC gaps, identity mismatches and status discrepancies require a verification-case link; other quality issues may have no case.';

COMMENT ON TABLE silver.data_lineage_record IS 'One input-version contribution to an output version or attribute. Retain the transformation rule and input/output values. Aggregates record every contributing input. Reference fields identify records across layers; they are validated references, not ordinary FKs.';

-- <<< END SOURCE FILE: sql/00_shared_setup/30_silver_source_integration_control.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/31_silver_customer_identity_resolution.sql

-- PostgreSQL 15+
-- Silver - Customer Master and Identity Resolution
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.customer_master (
  customer_id varchar(50) PRIMARY KEY NOT NULL,
  customer_full_name varchar(150) NOT NULL,
  date_of_birth date,
  email_address varchar(150),
  phone_number varchar(50),
  residential_address varchar(255),
  suburb_city varchar(100),
  state_region varchar(100),
  postcode varchar(20),
  country_code varchar(3),
  customer_status varchar(30) NOT NULL,
  customer_since_date date,
  created_at timestamp NOT NULL,
  last_updated_at timestamp NOT NULL
);

CREATE TABLE silver.source_customer_record (
  source_customer_record_id varchar(50) PRIMARY KEY NOT NULL,
  source_system_id varchar(50) NOT NULL,
  batch_id varchar(50) NOT NULL,
  source_customer_reference varchar(100) NOT NULL,
  source_record_version integer NOT NULL,
  bronze_record_reference varchar(300) NOT NULL,
  source_full_name varchar(150),
  source_date_of_birth date,
  source_email_address varchar(150),
  source_phone_number varchar(50),
  source_address varchar(255),
  source_last_updated_at timestamp,
  valid_from timestamp NOT NULL,
  valid_to timestamp,
  is_current_version boolean NOT NULL,
  record_hash varchar(128) NOT NULL
);

CREATE TABLE silver.customer_source_match (
  match_id varchar(50) PRIMARY KEY NOT NULL,
  source_customer_record_id varchar(50) NOT NULL,
  customer_id varchar(50),
  reviewed_by_user_id varchar(50),
  match_status varchar(20) NOT NULL,
  match_confidence_score decimal(5,4),
  match_rule varchar(150) NOT NULL,
  manual_review_flag boolean NOT NULL,
  effective_from timestamp NOT NULL,
  effective_to timestamp,
  is_current_match boolean NOT NULL,
  matched_at timestamp NOT NULL
);

CREATE TABLE silver.customer_attribute_source (
  attribute_source_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  match_id varchar(50) NOT NULL,
  attribute_name varchar(100) NOT NULL,
  selected_value text,
  survivorship_rule varchar(200) NOT NULL,
  effective_from timestamp NOT NULL,
  effective_to timestamp,
  is_current boolean NOT NULL
);

CREATE TABLE silver.customer_history (
  customer_history_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  attribute_source_id varchar(50),
  attribute_name varchar(100) NOT NULL,
  old_value text,
  new_value text,
  effective_from timestamp NOT NULL,
  effective_to timestamp,
  change_reason varchar(500) NOT NULL
);

CREATE UNIQUE INDEX source_customer_record_index_2 ON silver.source_customer_record (source_system_id, source_customer_reference, source_record_version);

CREATE UNIQUE INDEX customer_history_index_3 ON silver.customer_history (customer_id, attribute_name, effective_from);

COMMENT ON TABLE silver.customer_master IS 'One row per reconciled enterprise customer. This is the Silver golden customer record. Source-derived changes retain attribute provenance and history.';

COMMENT ON TABLE silver.source_customer_record IS 'One retained Silver version of a source customer. Unique by source + customer reference + version. Preserve old values; allow one current version per source identity. Bronze retains the original raw row.';

COMMENT ON TABLE silver.customer_source_match IS 'One retained matching decision. Across all versions of a source identity, allow at most one current ACCEPTED match. ACCEPTED requires customer_id; pending or rejected decisions may have no confirmed customer.';

COMMENT ON TABLE silver.customer_attribute_source IS 'One selected source for a customer attribute during an effective period. The match must have been ACCEPTED for the same customer when selected. Allow one current selected source per customer + attribute.';

COMMENT ON TABLE silver.customer_history IS 'One historical customer-attribute change. Retain old/new values and effective periods. When present, attribute_source_id must refer to the same customer and attribute. A manual correction requires a reason and lineage.';

-- <<< END SOURCE FILE: sql/00_shared_setup/31_silver_customer_identity_resolution.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/32_silver_banking_lending.sql

-- PostgreSQL 15+
-- Silver - Banking and Lending
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.banking_account (
  account_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  source_system_id varchar(50) NOT NULL,
  source_account_reference varchar(100) NOT NULL,
  account_type varchar(50) NOT NULL,
  account_status varchar(30) NOT NULL,
  current_balance decimal(20,2) NOT NULL,
  opened_date date NOT NULL,
  closed_date date,
  source_last_updated_at timestamp NOT NULL,
  as_of_date date NOT NULL,
  daily_income decimal(18,2),
  daily_cost decimal(18,2),
  credit_exposure decimal(18,2)
);

CREATE TABLE silver.account_transaction (
  transaction_id varchar(50) PRIMARY KEY NOT NULL,
  account_id varchar(50) NOT NULL,
  source_system_id varchar(50) NOT NULL,
  source_transaction_reference varchar(100) NOT NULL,
  transaction_date timestamp NOT NULL,
  transaction_type varchar(50) NOT NULL,
  transaction_amount decimal(20,2) NOT NULL,
  transaction_status varchar(30) NOT NULL
);

CREATE TABLE silver.loan (
  loan_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  source_system_id varchar(50) NOT NULL,
  source_loan_reference varchar(100) NOT NULL,
  loan_type varchar(50) NOT NULL,
  loan_status varchar(30) NOT NULL,
  original_amount decimal(20,2) NOT NULL,
  outstanding_balance decimal(20,2) NOT NULL,
  interest_rate decimal(9,6) NOT NULL,
  start_date date NOT NULL,
  maturity_date date,
  source_last_updated_at timestamp NOT NULL,
  as_of_date date NOT NULL,
  daily_income decimal(18,2),
  daily_cost decimal(18,2),
  credit_exposure decimal(18,2)
);

CREATE UNIQUE INDEX banking_account_index_4 ON silver.banking_account (source_system_id, source_account_reference);

CREATE UNIQUE INDEX account_transaction_index_5 ON silver.account_transaction (source_system_id, source_transaction_reference);

CREATE UNIQUE INDEX loan_index_6 ON silver.loan (source_system_id, source_loan_reference);

COMMENT ON TABLE silver.banking_account IS 'One current integrated account per source + account reference. One owner per account in the prototype. as_of_date dates the balance, daily income/cost and exposure; prior reporting inputs remain in lineage.';

COMMENT ON TABLE silver.account_transaction IS 'One transaction event. Source + transaction reference is unique. Each transaction belongs to an account; account and transaction source identifiers must agree. Transaction movements are not automatically income.';

COMMENT ON TABLE silver.loan IS 'One current integrated loan per source + loan reference. One borrower per loan in the prototype. as_of_date dates the outstanding balance, daily income/cost and exposure; retain prior reporting inputs in lineage.';

-- <<< END SOURCE FILE: sql/00_shared_setup/32_silver_banking_lending.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/33_silver_kyc_verification.sql

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

-- <<< END SOURCE FILE: sql/00_shared_setup/33_silver_kyc_verification.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/34_silver_aml_customer_risk.sql

-- PostgreSQL 15+
-- Silver - AML and Customer Risk
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.aml_screening_result (
  aml_screening_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50),
  source_customer_record_id varchar(50),
  source_system_id varchar(50) NOT NULL,
  source_screening_reference varchar(100) NOT NULL,
  screening_type varchar(50) NOT NULL,
  screening_date timestamp NOT NULL,
  screening_result varchar(50) NOT NULL,
  match_score decimal(5,4),
  provider_reference varchar(150),
  review_required_flag boolean NOT NULL
);

CREATE TABLE silver.aml_case (
  aml_case_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50),
  source_customer_record_id varchar(50),
  aml_screening_id varchar(50),
  assigned_user_id varchar(50),
  trigger_type varchar(50) NOT NULL,
  trigger_reference varchar(150) NOT NULL,
  case_type varchar(50) NOT NULL,
  case_status varchar(30) NOT NULL,
  risk_level varchar(30) NOT NULL,
  opened_at timestamp NOT NULL,
  closed_at timestamp,
  case_outcome varchar(1000)
);

CREATE TABLE silver.customer_risk_assessment (
  risk_assessment_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  assessment_date timestamp NOT NULL,
  assessment_version integer NOT NULL,
  risk_score decimal(7,4) NOT NULL,
  risk_rating varchar(30) NOT NULL,
  credit_exposure decimal(20,2) NOT NULL,
  aml_risk_rating varchar(30) NOT NULL,
  kyc_risk_rating varchar(30) NOT NULL,
  assessment_reason varchar(500) NOT NULL,
  assessment_rule varchar(150) NOT NULL,
  assessment_rule_version varchar(30) NOT NULL,
  valid_until timestamp,
  recorded_at timestamp NOT NULL
);

CREATE UNIQUE INDEX aml_screening_result_index_8 ON silver.aml_screening_result (source_system_id, source_screening_reference);

CREATE UNIQUE INDEX customer_risk_assessment_index_9 ON silver.customer_risk_assessment (customer_id, assessment_date, assessment_version);

COMMENT ON TABLE silver.aml_screening_result IS 'One screening event, unique by source + screening reference. Require a customer or source customer record; both must agree if supplied. A screening alert does not itself confirm an AML issue.';

COMMENT ON TABLE silver.aml_case IS 'One AML investigation. Require a customer, source customer record or screening reference. Screening is optional for another documented trigger. Supplied subject links must agree; CLOSED requires closed_at.';

COMMENT ON TABLE silver.customer_risk_assessment IS 'One assessment version for a customer and assessment time. Retain prior assessments. A report uses the latest eligible assessment at its reporting cut-off, excluding future or expired assessments.';

-- <<< END SOURCE FILE: sql/00_shared_setup/34_silver_aml_customer_risk.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/35_silver_security_user_access.sql

-- PostgreSQL 15+
-- Silver - Security and User Access
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.role (
  role_id varchar(50) PRIMARY KEY NOT NULL,
  role_name varchar(100) NOT NULL,
  role_description varchar(500)
);

CREATE TABLE silver.user_account (
  user_id varchar(50) PRIMARY KEY NOT NULL,
  role_id varchar(50) NOT NULL,
  username varchar(100) NOT NULL,
  full_name varchar(150) NOT NULL,
  email_address varchar(150),
  department varchar(100),
  account_status varchar(30) NOT NULL,
  created_at timestamp NOT NULL,
  last_login_at timestamp
);

CREATE TABLE silver.access_audit_log (
  audit_id varchar(50) PRIMARY KEY NOT NULL,
  user_id varchar(50),
  role_id varchar(50),
  actor_identifier varchar(150) NOT NULL,
  query_reference varchar(150),
  action_type varchar(50) NOT NULL,
  resource_name varchar(200) NOT NULL,
  record_reference varchar(150),
  event_timestamp timestamp NOT NULL,
  success_flag boolean NOT NULL,
  ip_address varchar(50)
);

CREATE UNIQUE INDEX role_index_10 ON silver.role (role_name);

CREATE UNIQUE INDEX user_account_index_11 ON silver.user_account (username);

COMMENT ON TABLE silver.role IS 'One prototype access role. role_name is unique.';

COMMENT ON TABLE silver.user_account IS 'One internal user with one primary role in the prototype. username is unique. Internal users are distinct from bank customers.';

COMMENT ON TABLE silver.access_audit_log IS 'One auditable access, query or action event. Append-only. Preserve actor and role at the event time. user_id may be null for an unidentified actor; query_reference is optional for non-query actions.';

-- <<< END SOURCE FILE: sql/00_shared_setup/35_silver_security_user_access.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/40_gold_reporting_analytics.sql

-- PostgreSQL 15+
-- Gold - Reporting and Analytics
-- Split from Untitled.sql according to the report's functional domains.
-- Run after every Silver domain file.

CREATE TABLE gold.dim_customer (
  customer_key bigint PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  customer_full_name varchar(150) NOT NULL,
  customer_status varchar(30) NOT NULL,
  effective_from timestamp NOT NULL,
  effective_to timestamp,
  current_flag boolean NOT NULL
);

CREATE TABLE gold.fact_customer_snapshot (
  customer_snapshot_id varchar(50) PRIMARY KEY NOT NULL,
  customer_id varchar(50) NOT NULL,
  customer_key bigint NOT NULL,
  risk_assessment_id varchar(50),
  snapshot_date date NOT NULL,
  total_account_balance decimal(20,2) NOT NULL,
  total_outstanding_loans decimal(20,2) NOT NULL,
  total_overdraft_balance decimal(20,2) NOT NULL,
  total_debt decimal(20,2) NOT NULL,
  banking_credit_exposure decimal(20,2),
  lending_credit_exposure decimal(20,2),
  total_credit_exposure decimal(20,2),
  total_income decimal(20,2),
  total_cost decimal(20,2),
  net_profit decimal(20,2),
  financial_data_status varchar(20) NOT NULL,
  risk_score decimal(7,4),
  risk_rating varchar(30),
  kyc_status varchar(30) NOT NULL,
  aml_risk_level varchar(30),
  calculated_at timestamp NOT NULL
);

CREATE TABLE gold.fact_compliance_exception (
  exception_fact_id varchar(50) PRIMARY KEY NOT NULL,
  customer_key bigint,
  verification_case_id varchar(50),
  aml_case_id varchar(50),
  exception_source_type varchar(20) NOT NULL,
  exception_type varchar(50) NOT NULL,
  exception_status varchar(30) NOT NULL,
  severity varchar(30) NOT NULL,
  opened_date date NOT NULL,
  resolved_date date,
  as_of_date date NOT NULL,
  days_open integer NOT NULL,
  last_updated_at timestamp NOT NULL
);

CREATE UNIQUE INDEX dim_customer_index_12 ON gold.dim_customer (customer_id, effective_from);

CREATE UNIQUE INDEX fact_customer_snapshot_index_13 ON gold.fact_customer_snapshot (customer_id, snapshot_date);

CREATE UNIQUE INDEX fact_compliance_exception_index_14 ON gold.fact_compliance_exception (verification_case_id);

CREATE UNIQUE INDEX fact_compliance_exception_index_15 ON gold.fact_compliance_exception (aml_case_id);

COMMENT ON TABLE gold.dim_customer IS 'One reporting version of a customer. Retain non-overlapping effective periods and one current version. customer_id links each version to the Silver golden customer.';

COMMENT ON TABLE gold.fact_customer_snapshot IS 'One customer per snapshot date; customer_id + snapshot_date is unique. Dimension and assessment references must identify that customer. Match all product inputs to the reporting date; incomplete financial inputs remain unknown.';

COMMENT ON TABLE gold.fact_compliance_exception IS 'One accumulating row per originating case. Exactly one source-case FK is required and each case occurs once. customer_key may be null until identity is confirmed. Refresh days_open using as_of_date.';

-- <<< END SOURCE FILE: sql/00_shared_setup/40_gold_reporting_analytics.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/45_create_reporting_views.sql

-- PostgreSQL 15+
-- Reserved for the two derived views specified in the report:
--   gold.vw_single_customer
--   gold.vw_customer_account_history
-- Untitled.sql contains no view definitions, so implementation is deferred
-- until the Gold loading and reporting rules are agreed.

-- <<< END SOURCE FILE: sql/00_shared_setup/45_create_reporting_views.sql

-- >>> BEGIN SOURCE FILE: sql/00_shared_setup/49_add_foreign_keys.sql

-- PostgreSQL 15+
-- Add all relationships only after Source, Bronze, Silver and Gold tables exist.
-- Keeping cross-domain foreign keys here makes each domain file independently
-- maintainable and prevents execution-order failures.

ALTER TABLE silver.ingestion_batch ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.cdc_change_event ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (verification_case_id) REFERENCES silver.special_verification_case (verification_case_id);

ALTER TABLE silver.data_lineage_record ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.data_lineage_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.source_customer_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (reviewed_by_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.customer_attribute_source ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.customer_history ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.banking_account ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.banking_account ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.account_transaction ADD FOREIGN KEY (account_id) REFERENCES silver.banking_account (account_id);

ALTER TABLE silver.account_transaction ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.loan ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.loan ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (reviewed_by) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (match_id) REFERENCES silver.customer_source_match (match_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (kyc_verification_id) REFERENCES silver.kyc_verification_record (kyc_verification_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (assigned_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (aml_screening_id) REFERENCES silver.aml_screening_result (aml_screening_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (assigned_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.customer_risk_assessment ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.user_account ADD FOREIGN KEY (role_id) REFERENCES silver.role (role_id);

ALTER TABLE silver.access_audit_log ADD FOREIGN KEY (user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.access_audit_log ADD FOREIGN KEY (role_id) REFERENCES silver.role (role_id);

ALTER TABLE gold.dim_customer ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (risk_assessment_id) REFERENCES silver.customer_risk_assessment (risk_assessment_id);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (customer_key) REFERENCES gold.dim_customer (customer_key);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (verification_case_id) REFERENCES silver.special_verification_case (verification_case_id);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (aml_case_id) REFERENCES silver.aml_case (aml_case_id);

ALTER TABLE silver.cdc_change_event ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.source_customer_record ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.customer_attribute_source ADD FOREIGN KEY (match_id) REFERENCES silver.customer_source_match (match_id);

ALTER TABLE silver.customer_history ADD FOREIGN KEY (attribute_source_id) REFERENCES silver.customer_attribute_source (attribute_source_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (customer_key) REFERENCES gold.dim_customer (customer_key);

-- <<< END SOURCE FILE: sql/00_shared_setup/49_add_foreign_keys.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/01_add_incremental_controls.sql

-- Prepares the control objects required by the incremental-load pipeline.

-- Enforces valid batch types, lifecycle states, record counts and CDC operations.
DO $controls$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_load_type'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_load_type
      CHECK (load_type IN ('INITIAL', 'SIMULATED_CDC'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_status'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_status
      CHECK (load_status IN ('RUNNING', 'SUCCEEDED', 'FAILED'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_counts'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_counts
      CHECK (
        records_received >= 0
        AND records_processed >= 0
        AND records_processed <= records_received
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_lifecycle'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_lifecycle
      CHECK (
        (load_status = 'RUNNING'
          AND completed_at IS NULL
          AND watermark_end IS NULL)
        OR
        (load_status = 'SUCCEEDED'
          AND completed_at IS NOT NULL
          AND watermark_end IS NOT NULL)
        OR
        (load_status = 'FAILED'
          AND completed_at IS NOT NULL
          AND watermark_end IS NULL)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_cdc_operation_type'
      AND conrelid = 'silver.cdc_change_event'::regclass
  ) THEN
    ALTER TABLE silver.cdc_change_event
      ADD CONSTRAINT ck_cdc_operation_type
      CHECK (operation_type IN ('I', 'U', 'D'));
  END IF;
END
$controls$;

-- Supports batch-status, watermark and Bronze CDC lookups.
CREATE INDEX IF NOT EXISTS ix_ingestion_batch_source_status_completed
  ON silver.ingestion_batch
  (source_system_id, load_status, completed_at DESC);

CREATE INDEX IF NOT EXISTS ix_bronze_cdc_batch
  ON bronze.cdc_change_event (batch_id);

-- Exposes the most recent committed watermark for each source system.
CREATE OR REPLACE VIEW silver.vw_latest_successful_watermark AS
SELECT DISTINCT ON (source_system_id)
  source_system_id,
  batch_id,
  watermark_end,
  completed_at
FROM silver.ingestion_batch
WHERE load_status = 'SUCCEEDED'
ORDER BY source_system_id, completed_at DESC, batch_id DESC;

COMMENT ON VIEW silver.vw_latest_successful_watermark IS
  'Latest committed watermark per source; failed and running batches are excluded.';

-- <<< END SOURCE FILE: sql/module1_hongfei/01_add_incremental_controls.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/02_seed_source_data.sql

-- Seeds the simulated Source layer with idempotent writes.
-- The invalid CDC-019 operation is preserved to exercise the failure path.

BEGIN;

-- Loads source-system definitions.
INSERT INTO source_systems.source_system (
  source_system_id,
  system_name,
  system_type,
  system_description,
  system_owner,
  active_flag
)
VALUES
  ('CRM', 'CRM Banking', 'CUSTOMER_AND_ACCOUNTS', 'Synthetic CRM and banking source', 'Prototype team', TRUE),
  ('LEND', 'Lending', 'LOANS', 'Synthetic lending source', 'Prototype team', TRUE),
  ('AMLKYC', 'AML/KYC', 'COMPLIANCE', 'Synthetic verification and screening source', 'Prototype team', TRUE)
ON CONFLICT (source_system_id) DO UPDATE SET
  system_name = EXCLUDED.system_name,
  system_type = EXCLUDED.system_type,
  system_description = EXCLUDED.system_description,
  system_owner = EXCLUDED.system_owner,
  active_flag = EXCLUDED.active_flag;

-- Loads ingestion-batch definitions.
INSERT INTO source_systems.ingestion_batch (
  batch_id,
  source_system_id,
  load_type,
  started_at,
  completed_at,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
)
VALUES
  ('B1-CRM', 'CRM', 'INITIAL', '2026-09-01T08:00:00', '2026-09-01T08:30:00', 'SUCCEEDED', 34, 34, NULL, '2026-09-01'),
  ('B1-LEND', 'LEND', 'INITIAL', '2026-09-01T08:00:00', '2026-09-01T08:30:00', 'SUCCEEDED', 12, 12, NULL, '2026-09-01'),
  ('B1-AMLKYC', 'AMLKYC', 'INITIAL', '2026-09-01T08:00:00', '2026-09-01T08:30:00', 'SUCCEEDED', 27, 27, NULL, '2026-09-01'),
  ('B2-CRM', 'CRM', 'SIMULATED_CDC', '2026-09-15T08:00:00', '2026-09-15T08:30:00', 'SUCCEEDED', 12, 12, '2026-09-01', '2026-09-15'),
  ('B2-LEND', 'LEND', 'SIMULATED_CDC', '2026-09-15T08:00:00', '2026-09-15T08:30:00', 'SUCCEEDED', 6, 6, '2026-09-01', '2026-09-15'),
  ('B2-AMLKYC', 'AMLKYC', 'SIMULATED_CDC', '2026-09-15T08:00:00', '2026-09-15T08:30:00', 'SUCCEEDED', 1, 1, '2026-09-01', '2026-09-15')
ON CONFLICT (batch_id) DO UPDATE SET
  source_system_id = EXCLUDED.source_system_id,
  load_type = EXCLUDED.load_type,
  started_at = EXCLUDED.started_at,
  completed_at = EXCLUDED.completed_at,
  load_status = EXCLUDED.load_status,
  records_received = EXCLUDED.records_received,
  records_processed = EXCLUDED.records_processed,
  watermark_start = EXCLUDED.watermark_start,
  watermark_end = EXCLUDED.watermark_end;

-- Loads simulated CDC events.
INSERT INTO source_systems.cdc_change_event (
  change_event_id,
  source_system_id,
  batch_id,
  source_entity_name,
  source_record_reference,
  source_version_reference,
  operation_type,
  event_sequence,
  source_change_time,
  captured_at,
  change_payload
)
VALUES
  ('CDC-001', 'CRM', 'B2-CRM', 'CUSTOMER', 'CRM-006', '2', 'U', 1, '2026-09-15T07:10:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-CRM-011"}'),
  ('CDC-002', 'CRM', 'B2-CRM', 'CUSTOMER', 'CRM-007', '2', 'D', 2, '2026-09-15T07:15:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-CRM-012"}'),
  ('CDC-003', 'CRM', 'B2-CRM', 'CUSTOMER', 'CRM-011', '1', 'I', 3, '2026-09-15T07:20:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-CRM-013"}'),
  ('CDC-004', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-001', '2', 'U', 1, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-002"}'),
  ('CDC-005', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-003', '2', 'U', 2, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-004"}'),
  ('CDC-006', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-004', '2', 'U', 3, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-006"}'),
  ('CDC-007', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-005', '2', 'U', 4, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-008"}'),
  ('CDC-008', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-006', '2', 'U', 5, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-010"}'),
  ('CDC-009', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-010', '2', 'U', 6, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-012"}'),
  ('CDC-010', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-012', '2', 'U', 7, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-014"}'),
  ('CDC-011', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-013', '2', 'U', 8, '2026-09-15T07:45:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-016"}'),
  ('CDC-012', 'CRM', 'B2-CRM', 'ACCOUNT', 'ACC-011', '1', 'I', 9, '2026-09-15T07:46:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-ACC-017"}'),
  ('CDC-013', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-001', '2', 'U', 1, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-002"}'),
  ('CDC-014', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-002', '2', 'U', 2, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-004"}'),
  ('CDC-015', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-005', '2', 'U', 3, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-006"}'),
  ('CDC-016', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-008', '2', 'U', 4, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-008"}'),
  ('CDC-017', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-010', '2', 'U', 5, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-010"}'),
  ('CDC-018', 'LEND', 'B2-LEND', 'LOAN', 'LOAN-012', '2', 'U', 6, '2026-09-15T07:48:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-LOAN-012"}'),
  ('CDC-019', 'AMLKYC', 'B2-AMLKYC', 'AML_SCREENING', 'SCR-005-2', '1', '', 1, '2026-09-15T07:25:00', '2026-09-15T08:25:00', '{"bronze_record_reference":"BR-SCR-010"}')
ON CONFLICT (change_event_id) DO UPDATE SET
  source_system_id = EXCLUDED.source_system_id,
  batch_id = EXCLUDED.batch_id,
  source_entity_name = EXCLUDED.source_entity_name,
  source_record_reference = EXCLUDED.source_record_reference,
  source_version_reference = EXCLUDED.source_version_reference,
  operation_type = EXCLUDED.operation_type,
  event_sequence = EXCLUDED.event_sequence,
  source_change_time = EXCLUDED.source_change_time,
  captured_at = EXCLUDED.captured_at,
  change_payload = EXCLUDED.change_payload;

-- Loads raw CRM customers.
INSERT INTO source_systems.raw_crm_customer (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_customer_reference,
  source_record_version,
  operation_type,
  source_full_name,
  source_date_of_birth,
  source_email_address,
  source_phone_number,
  source_address,
  record_status,
  source_last_updated_at,
  ingested_at
)
VALUES
  ('BR-CRM-001', 'CRM', 'B1-CRM', 'CRM-001', 1, 'I', 'Alice Wong', '1985-03-12', 'alice.wong@example.test', '0412001001', '18 Harbour Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-002', 'CRM', 'B1-CRM', 'CRM-002', 1, 'I', 'Daniel Lee', '1988-04-11', 'daniel.lee@example.test', '0412001002', '42 King Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-003', 'CRM', 'B1-CRM', 'CRM-003', 1, 'I', 'Maya Patel', '1990-07-23', 'maya.patel@example.test', '0412001003', '4 Old Wharf Road, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-004', 'CRM', 'B1-CRM', 'CRM-004', 1, 'I', 'Noah Chen', '1979-11-05', 'noah.chen@example.test', '0412001004', '5 Garden Road, Parramatta NSW 2150', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-005', 'CRM', 'B1-CRM', 'CRM-005', 1, 'I', 'Olivia Brooks', '1992-06-17', 'olivia.brooks@example.test', '0412001005', '11 Lake Road, Chatswood NSW 2067', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-006', 'CRM', 'B1-CRM', 'CRM-006', 1, 'I', 'Ethan Nguyen', '1983-02-09', 'ethan.nguyen@example.test', '0412001006', '27 Pine Street, Newtown NSW 2042', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-007', 'CRM', 'B1-CRM', 'CRM-007', 1, 'I', 'Ava Morgan', '1995-09-28', 'ava.morgan@example.test', '0412001007', '3 Hill Street, Surry Hills NSW 2010', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-008', 'CRM', 'B1-CRM', 'CRM-010', 1, 'I', 'Grace Wilson', '1981-12-04', 'grace.wilson@example.test', '0412001010', '12 Park Avenue, Liverpool NSW 2170', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-009', 'CRM', 'B1-CRM', 'CRM-012', 1, 'I', 'Leo Martin', '1968-10-07', 'leo.martin@example.test', '0412001012', '16 Bay Street, Rockdale NSW 2216', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-010', 'CRM', 'B1-CRM', 'CRM-013', 1, 'I', 'Harper Rose', '1987-03-02', 'harper.rose@example.test', '0412001013', '19 Market Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:30:00', '2026-09-01T08:10:00'),
  ('BR-CRM-011', 'CRM', 'B2-CRM', 'CRM-006', 2, 'U', 'Ethan Nguyen', '1983-02-09', 'ethan.nguyen.new@example.test', '0412001006', '27 Pine Street, Newtown NSW 2042', 'ACTIVE', '2026-09-15T07:10:00', '2026-09-15T08:10:00'),
  ('BR-CRM-012', 'CRM', 'B2-CRM', 'CRM-007', 2, 'D', 'Ava Morgan', '1995-09-28', 'ava.morgan@example.test', '0412001007', '3 Hill Street, Surry Hills NSW 2010', 'DELETED', '2026-09-15T07:15:00', '2026-09-15T08:11:00'),
  ('BR-CRM-013', 'CRM', 'B2-CRM', 'CRM-011', 1, 'I', 'Mia Rivera', '1993-05-20', 'mia.rivera@example.test', '0412001011', '22 Church Street, Ryde NSW 2112', 'ACTIVE', '2026-09-15T07:20:00', '2026-09-15T08:12:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw lending customers.
INSERT INTO source_systems.raw_lending_customer (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_customer_reference,
  source_record_version,
  operation_type,
  source_full_name,
  source_date_of_birth,
  source_email_address,
  source_phone_number,
  source_address,
  record_status,
  source_last_updated_at,
  ingested_at
)
VALUES
  ('BR-LEND-C-001', 'LEND', 'B1-LEND', 'LEND-001', 1, 'I', 'WONG, ALICE', '1985-03-12', 'alice.wong@example.test', '0412001001', '18 Harbour Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00'),
  ('BR-LEND-C-002', 'LEND', 'B1-LEND', 'LEND-002', 1, 'I', 'Daniel Lee', '1988-04-17', 'daniel.l@example.test', '0412001002', '42 King Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00'),
  ('BR-LEND-C-003', 'LEND', 'B1-LEND', 'LEND-005', 1, 'I', 'Olivia Brooks', '1992-06-17', 'olivia.brooks@example.test', '0412001005', '11 Lake Road, Chatswood NSW 2067', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00'),
  ('BR-LEND-C-004', 'LEND', 'B1-LEND', 'LEND-008', 1, 'I', 'Liam Scott', '1975-08-14', 'liam.scott@example.test', '0412001008', '61 River Road, Penrith NSW 2750', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00'),
  ('BR-LEND-C-005', 'LEND', 'B1-LEND', 'LEND-010', 1, 'I', 'Grace Wilson', '1981-12-04', 'grace.wilson@example.test', '0412001010', '12 Park Avenue, Liverpool NSW 2170', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00'),
  ('BR-LEND-C-006', 'LEND', 'B1-LEND', 'LEND-012', 1, 'I', 'Leo Martin', '1968-10-07', 'leo.martin@example.test', '0412001012', '16 Bay Street, Rockdale NSW 2216', 'ACTIVE', '2026-09-01T07:35:00', '2026-09-01T08:12:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw AML/KYC customers.
INSERT INTO source_systems.raw_aml_kyc_customer (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_customer_reference,
  source_record_version,
  operation_type,
  source_full_name,
  source_date_of_birth,
  source_email_address,
  source_phone_number,
  source_address,
  record_status,
  source_last_updated_at,
  ingested_at
)
VALUES
  ('BR-AML-C-001', 'AMLKYC', 'B1-AMLKYC', 'KYC-001', 1, 'I', 'Alice Wong', '1985-03-12', 'alice.wong@example.test', '0412001001', '18 Harbour Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-002', 'AMLKYC', 'B1-AMLKYC', 'KYC-003', 1, 'I', 'Maya Patel', '1990-07-23', 'maya.patel@example.test', '0412001003', '9 Ocean Avenue, Bondi NSW 2026', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-003', 'AMLKYC', 'B1-AMLKYC', 'KYC-004', 1, 'I', 'Noah Chen', '1979-11-05', 'noah.chen@example.test', '0412001004', '5 Garden Road, Parramatta NSW 2150', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-004', 'AMLKYC', 'B1-AMLKYC', 'KYC-005', 1, 'I', 'Olivia Brooks', '1992-06-17', 'olivia.brooks@example.test', '0412001005', '11 Lake Road, Chatswood NSW 2067', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-005', 'AMLKYC', 'B1-AMLKYC', 'KYC-006', 1, 'I', 'Ethan Nguyen', '1983-02-09', 'ethan.nguyen@example.test', '0412001006', '27 Pine Street, Newtown NSW 2042', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-006', 'AMLKYC', 'B1-AMLKYC', 'KYC-009', 1, 'I', 'Zoe Kim', '1999-01-31', 'zoe.kim@example.test', '0412001009', '8 Bridge Street, Sydney NSW 2000', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-007', 'AMLKYC', 'B1-AMLKYC', 'KYC-010', 1, 'I', 'Grace Wilson', '1981-12-04', 'grace.wilson@example.test', '0412001010', '12 Park Avenue, Liverpool NSW 2170', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-008', 'AMLKYC', 'B1-AMLKYC', 'KYC-012', 1, 'I', 'Leo Martin', '1968-10-07', 'leo.martin@example.test', '0412001012', '16 Bay Street, Rockdale NSW 2216', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00'),
  ('BR-AML-C-009', 'AMLKYC', 'B1-AMLKYC', 'KYC-014', 1, 'I', 'Lucas Park', '1991-04-19', 'lucas.park@example.test', '0412001014', '7 North Street, Burwood NSW 2134', 'ACTIVE', '2026-09-01T07:40:00', '2026-09-01T08:14:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw banking-account snapshots.
INSERT INTO source_systems.raw_banking_account_snapshot (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_account_reference,
  source_customer_reference,
  source_record_version,
  operation_type,
  account_type,
  account_status,
  currency_code,
  current_balance,
  opened_date,
  closed_date,
  as_of_date,
  daily_income,
  daily_cost,
  credit_exposure,
  source_last_updated_at,
  ingested_at
)
VALUES
  ('BR-ACC-001', 'CRM', 'B1-CRM', 'ACC-001', 'CRM-001', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 12500.00, '2022-03-01', NULL, '2026-09-01', 25.00, 8.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-002', 'CRM', 'B2-CRM', 'ACC-001', 'CRM-001', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 12575.00, '2022-03-01', NULL, '2026-09-15', 25.00, 8.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-003', 'CRM', 'B1-CRM', 'ACC-003', 'CRM-003', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 4800.00, '2022-03-01', NULL, '2026-09-01', 28.00, 9.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-004', 'CRM', 'B2-CRM', 'ACC-003', 'CRM-003', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 4950.00, '2022-03-01', NULL, '2026-09-15', 28.00, 9.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-005', 'CRM', 'B1-CRM', 'ACC-004', 'CRM-004', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 9100.00, '2022-03-01', NULL, '2026-09-01', 31.00, 10.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-006', 'CRM', 'B2-CRM', 'ACC-004', 'CRM-004', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 9325.00, '2022-03-01', NULL, '2026-09-15', 31.00, 10.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-007', 'CRM', 'B1-CRM', 'ACC-005', 'CRM-005', 1, 'I', 'CURRENT', 'OPEN', 'AUD', -1400.00, '2022-03-01', NULL, '2026-09-01', 34.00, 11.00, 1500.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-008', 'CRM', 'B2-CRM', 'ACC-005', 'CRM-005', 2, 'U', 'CURRENT', 'OPEN', 'AUD', -1100.00, '2022-03-01', NULL, '2026-09-15', 34.00, 11.00, 1500.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-009', 'CRM', 'B1-CRM', 'ACC-006', 'CRM-006', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 2200.00, '2022-03-01', NULL, '2026-09-01', 37.00, 12.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-010', 'CRM', 'B2-CRM', 'ACC-006', 'CRM-006', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 2575.00, '2022-03-01', NULL, '2026-09-15', 37.00, 12.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-011', 'CRM', 'B1-CRM', 'ACC-010', 'CRM-010', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 17700.00, '2022-03-01', NULL, '2026-09-01', 40.00, 13.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-012', 'CRM', 'B2-CRM', 'ACC-010', 'CRM-010', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 18150.00, '2022-03-01', NULL, '2026-09-15', 40.00, 13.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-013', 'CRM', 'B1-CRM', 'ACC-012', 'CRM-012', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 3300.00, '2022-03-01', NULL, '2026-09-01', 43.00, 14.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-014', 'CRM', 'B2-CRM', 'ACC-012', 'CRM-012', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 3825.00, '2022-03-01', NULL, '2026-09-15', 43.00, 14.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-015', 'CRM', 'B1-CRM', 'ACC-013', 'CRM-013', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 7600.00, '2022-03-01', NULL, '2026-09-01', 46.00, 15.00, 0.00, '2026-09-01T07:45:00', '2026-09-01T08:16:00'),
  ('BR-ACC-016', 'CRM', 'B2-CRM', 'ACC-013', 'CRM-013', 2, 'U', 'SAVINGS', 'OPEN', 'AUD', 8200.00, '2022-03-01', NULL, '2026-09-15', 46.00, 15.00, 0.00, '2026-09-15T07:45:00', '2026-09-15T08:16:00'),
  ('BR-ACC-017', 'CRM', 'B2-CRM', 'ACC-011', 'CRM-011', 1, 'I', 'SAVINGS', 'OPEN', 'AUD', 5200.00, '2026-09-15', NULL, '2026-09-15', 14.00, 5.00, 0.00, '2026-09-15T07:46:00', '2026-09-15T08:17:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw loan snapshots.
INSERT INTO source_systems.raw_loan_snapshot (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_loan_reference,
  source_customer_reference,
  source_record_version,
  operation_type,
  loan_type,
  loan_status,
  original_amount,
  outstanding_balance,
  interest_rate,
  start_date,
  maturity_date,
  as_of_date,
  daily_income,
  daily_cost,
  credit_exposure,
  source_last_updated_at,
  ingested_at
)
VALUES
  ('BR-LOAN-001', 'LEND', 'B1-LEND', 'LOAN-001', 'LEND-001', 1, 'I', 'HOME', 'ACTIVE', 220000.00, 198000.00, 0.052500, '2023-01-15', '2033-01-15', '2026-09-01', 38.00, 11.00, 198000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-002', 'LEND', 'B2-LEND', 'LOAN-001', 'LEND-001', 2, 'U', 'HOME', 'ACTIVE', 220000.00, 193000.00, 0.052500, '2023-01-15', '2033-01-15', '2026-09-15', 38.00, 11.00, 193000.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00'),
  ('BR-LOAN-003', 'LEND', 'B1-LEND', 'LOAN-002', 'LEND-002', 1, 'I', 'PERSONAL', 'ACTIVE', 85000.00, 70000.00, 0.055000, '2023-01-15', '2033-01-15', '2026-09-01', 43.00, 13.00, 70000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-004', 'LEND', 'B2-LEND', 'LOAN-002', 'LEND-002', 2, 'U', 'PERSONAL', 'ACTIVE', 85000.00, 69300.00, 0.055000, '2023-01-15', '2033-01-15', '2026-09-15', 43.00, 13.00, 69300.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00'),
  ('BR-LOAN-005', 'LEND', 'B1-LEND', 'LOAN-005', 'LEND-005', 1, 'I', 'HOME', 'ACTIVE', 125000.00, 112000.00, 0.057500, '2023-01-15', '2033-01-15', '2026-09-01', 48.00, 15.00, 112000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-006', 'LEND', 'B2-LEND', 'LOAN-005', 'LEND-005', 2, 'U', 'HOME', 'ACTIVE', 125000.00, 111300.00, 0.057500, '2023-01-15', '2033-01-15', '2026-09-15', 48.00, 15.00, 111300.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00'),
  ('BR-LOAN-007', 'LEND', 'B1-LEND', 'LOAN-008', 'LEND-008', 1, 'I', 'PERSONAL', 'ACTIVE', 48000.00, 34000.00, 0.060000, '2023-01-15', '2033-01-15', '2026-09-01', 53.00, 17.00, 34000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-008', 'LEND', 'B2-LEND', 'LOAN-008', 'LEND-008', 2, 'U', 'PERSONAL', 'ACTIVE', 48000.00, 33300.00, 0.060000, '2023-01-15', '2033-01-15', '2026-09-15', 53.00, 17.00, 33300.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00'),
  ('BR-LOAN-009', 'LEND', 'B1-LEND', 'LOAN-010', 'LEND-010', 1, 'I', 'HOME', 'ACTIVE', 310000.00, 278000.00, 0.062500, '2023-01-15', '2033-01-15', '2026-09-01', 58.00, 19.00, 278000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-010', 'LEND', 'B2-LEND', 'LOAN-010', 'LEND-010', 2, 'U', 'HOME', 'ACTIVE', 310000.00, 277300.00, 0.062500, '2023-01-15', '2033-01-15', '2026-09-15', 58.00, 19.00, 277300.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00'),
  ('BR-LOAN-011', 'LEND', 'B1-LEND', 'LOAN-012', 'LEND-012', 1, 'I', 'PERSONAL', 'ACTIVE', 65000.00, 54000.00, 0.065000, '2023-01-15', '2033-01-15', '2026-09-01', 63.00, 21.00, 54000.00, '2026-09-01T07:48:00', '2026-09-01T08:19:00'),
  ('BR-LOAN-012', 'LEND', 'B2-LEND', 'LOAN-012', 'LEND-012', 2, 'U', 'PERSONAL', 'ACTIVE', 65000.00, 53300.00, 0.065000, '2023-01-15', '2033-01-15', '2026-09-15', 63.00, 21.00, 53300.00, '2026-09-15T07:48:00', '2026-09-15T08:19:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw account transactions.
INSERT INTO source_systems.raw_account_transaction (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_transaction_reference,
  source_account_reference,
  transaction_date,
  transaction_type,
  transaction_amount,
  transaction_status,
  ingested_at
)
VALUES
  ('BR-TXN-001', 'CRM', 'B1-CRM', 'TXN-001-1', 'ACC-001', '2026-09-01T06:00:00', 'CREDIT', 120.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-002', 'CRM', 'B1-CRM', 'TXN-001-2', 'ACC-001', '2026-09-01T06:30:00', 'DEBIT', 45.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-003', 'CRM', 'B1-CRM', 'TXN-003-1', 'ACC-003', '2026-09-01T06:00:00', 'CREDIT', 129.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-004', 'CRM', 'B1-CRM', 'TXN-003-2', 'ACC-003', '2026-09-01T06:30:00', 'DEBIT', 54.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-005', 'CRM', 'B1-CRM', 'TXN-004-1', 'ACC-004', '2026-09-01T06:00:00', 'CREDIT', 138.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-006', 'CRM', 'B1-CRM', 'TXN-004-2', 'ACC-004', '2026-09-01T06:30:00', 'DEBIT', 63.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-007', 'CRM', 'B1-CRM', 'TXN-005-1', 'ACC-005', '2026-09-01T06:00:00', 'CREDIT', 147.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-008', 'CRM', 'B1-CRM', 'TXN-005-2', 'ACC-005', '2026-09-01T06:30:00', 'DEBIT', 72.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-009', 'CRM', 'B1-CRM', 'TXN-006-1', 'ACC-006', '2026-09-01T06:00:00', 'CREDIT', 156.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-010', 'CRM', 'B1-CRM', 'TXN-006-2', 'ACC-006', '2026-09-01T06:30:00', 'DEBIT', 81.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-011', 'CRM', 'B1-CRM', 'TXN-010-1', 'ACC-010', '2026-09-01T06:00:00', 'CREDIT', 165.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-012', 'CRM', 'B1-CRM', 'TXN-010-2', 'ACC-010', '2026-09-01T06:30:00', 'DEBIT', 90.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-013', 'CRM', 'B1-CRM', 'TXN-012-1', 'ACC-012', '2026-09-01T06:00:00', 'CREDIT', 174.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-014', 'CRM', 'B1-CRM', 'TXN-012-2', 'ACC-012', '2026-09-01T06:30:00', 'DEBIT', 99.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-015', 'CRM', 'B1-CRM', 'TXN-013-1', 'ACC-013', '2026-09-01T06:00:00', 'CREDIT', 183.00, 'POSTED', '2026-09-01T08:20:00'),
  ('BR-TXN-016', 'CRM', 'B1-CRM', 'TXN-013-2', 'ACC-013', '2026-09-01T06:30:00', 'DEBIT', 108.00, 'POSTED', '2026-09-01T08:20:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw KYC verification events.
INSERT INTO source_systems.raw_kyc_verification (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_kyc_reference,
  source_customer_reference,
  verification_type,
  verification_status,
  verification_date,
  expiry_date,
  risk_level_at_verification,
  reviewer_reference,
  ingested_at
)
VALUES
  ('BR-KYC-001', 'AMLKYC', 'B1-AMLKYC', 'VFY-001', 'KYC-001', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-002', 'AMLKYC', 'B1-AMLKYC', 'VFY-003', 'KYC-003', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-003', 'AMLKYC', 'B1-AMLKYC', 'VFY-004', 'KYC-004', 'IDENTITY_DOCUMENT', 'MISSING_DOCUMENT', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-004', 'AMLKYC', 'B1-AMLKYC', 'VFY-005', 'KYC-005', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'MEDIUM', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-005', 'AMLKYC', 'B1-AMLKYC', 'VFY-006', 'KYC-006', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-006', 'AMLKYC', 'B1-AMLKYC', 'VFY-009', 'KYC-009', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-007', 'AMLKYC', 'B1-AMLKYC', 'VFY-010', 'KYC-010', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-008', 'AMLKYC', 'B1-AMLKYC', 'VFY-012', 'KYC-012', 'IDENTITY_DOCUMENT', 'EXPIRED', '2026-09-01T07:00:00', '2026-08-15', 'LOW', NULL, '2026-09-01T08:22:00'),
  ('BR-KYC-009', 'AMLKYC', 'B1-AMLKYC', 'VFY-014', 'KYC-014', 'IDENTITY_DOCUMENT', 'VERIFIED', '2026-09-01T07:00:00', '2028-09-01', 'LOW', NULL, '2026-09-01T08:22:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Loads raw AML screening events.
INSERT INTO source_systems.raw_aml_screening (
  bronze_record_reference,
  source_system_id,
  batch_id,
  source_screening_reference,
  source_customer_reference,
  screening_type,
  screening_date,
  screening_result,
  match_score,
  provider_reference,
  review_required_flag,
  ingested_at
)
VALUES
  ('BR-SCR-001', 'AMLKYC', 'B1-AMLKYC', 'SCR-001-1', 'KYC-001', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-001', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-002', 'AMLKYC', 'B1-AMLKYC', 'SCR-003-1', 'KYC-003', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-003', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-003', 'AMLKYC', 'B1-AMLKYC', 'SCR-004-1', 'KYC-004', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-004', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-004', 'AMLKYC', 'B1-AMLKYC', 'SCR-005-1', 'KYC-005', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-005', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-005', 'AMLKYC', 'B1-AMLKYC', 'SCR-006-1', 'KYC-006', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-006', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-006', 'AMLKYC', 'B1-AMLKYC', 'SCR-009-1', 'KYC-009', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-009', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-007', 'AMLKYC', 'B1-AMLKYC', 'SCR-010-1', 'KYC-010', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-010', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-008', 'AMLKYC', 'B1-AMLKYC', 'SCR-012-1', 'KYC-012', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-012', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-009', 'AMLKYC', 'B1-AMLKYC', 'SCR-014-1', 'KYC-014', 'SANCTIONS', '2026-09-01T07:20:00', 'CLEAR', 0.0200, 'SYN-014', FALSE, '2026-09-01T08:23:00'),
  ('BR-SCR-010', 'AMLKYC', 'B2-AMLKYC', 'SCR-005-2', 'KYC-005', 'WATCHLIST', '2026-09-15T07:25:00', 'POTENTIAL_MATCH', 0.9200, 'SYN-HIT-005', TRUE, '2026-09-15T08:24:00')
ON CONFLICT (bronze_record_reference) DO NOTHING;

COMMIT;

-- <<< END SOURCE FILE: sql/module1_hongfei/02_seed_source_data.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/03_load_initial_bronze.sql

-- Loads initial B1 data into Bronze and publishes successful load controls to Silver.

BEGIN;

-- Retains source metadata and initial batch definitions in Bronze.
INSERT INTO bronze.source_system
SELECT *
FROM source_systems.source_system
ON CONFLICT (source_system_id) DO NOTHING;

INSERT INTO bronze.ingestion_batch
SELECT *
FROM source_systems.ingestion_batch
WHERE load_type = 'INITIAL'
ON CONFLICT (batch_id) DO NOTHING;

-- Copies all initial raw business records into the append-only Bronze tables.
INSERT INTO bronze.raw_crm_customer
SELECT r.*
FROM source_systems.raw_crm_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_lending_customer
SELECT r.*
FROM source_systems.raw_lending_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_aml_kyc_customer
SELECT r.*
FROM source_systems.raw_aml_kyc_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_banking_account_snapshot
SELECT r.*
FROM source_systems.raw_banking_account_snapshot r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_loan_snapshot
SELECT r.*
FROM source_systems.raw_loan_snapshot r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_account_transaction
SELECT r.*
FROM source_systems.raw_account_transaction r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_kyc_verification
SELECT r.*
FROM source_systems.raw_kyc_verification r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_aml_screening
SELECT r.*
FROM source_systems.raw_aml_screening r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Confirms each initial batch contains the number of raw records declared by its control row.
DO $validate_initial$
DECLARE
  v_batch source_systems.ingestion_batch%ROWTYPE;
  v_loaded integer;
BEGIN
  FOR v_batch IN
    SELECT *
    FROM source_systems.ingestion_batch
    WHERE load_type = 'INITIAL'
    ORDER BY batch_id
  LOOP
    SELECT count(*)
    INTO v_loaded
    FROM (
      SELECT 1 FROM bronze.raw_crm_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_lending_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_banking_account_snapshot WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_loan_snapshot WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_account_transaction WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = v_batch.batch_id
    ) loaded_rows;

    IF v_loaded <> v_batch.records_received THEN
      RAISE EXCEPTION
        'Initial batch % expected % records but Bronze contains %',
        v_batch.batch_id,
        v_batch.records_received,
        v_loaded;
    END IF;
  END LOOP;
END
$validate_initial$;

-- Publishes the authoritative source-system catalogue to Silver.
INSERT INTO silver.source_system (
  source_system_id,
  system_name,
  system_type,
  system_description,
  system_owner,
  active_flag
)
SELECT
  source_system_id,
  system_name,
  system_type,
  system_description,
  system_owner,
  active_flag
FROM bronze.source_system
ON CONFLICT (source_system_id) DO UPDATE SET
  system_name = EXCLUDED.system_name,
  system_type = EXCLUDED.system_type,
  system_description = EXCLUDED.system_description,
  system_owner = EXCLUDED.system_owner,
  active_flag = EXCLUDED.active_flag;

-- Marks validated initial batches as successfully processed in Silver.
INSERT INTO silver.ingestion_batch (
  batch_id,
  source_system_id,
  load_type,
  started_at,
  completed_at,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
)
SELECT
  batch_id,
  source_system_id,
  load_type,
  started_at,
  completed_at,
  'SUCCEEDED',
  records_received,
  records_received,
  watermark_start,
  watermark_end
FROM bronze.ingestion_batch
WHERE load_type = 'INITIAL'
ON CONFLICT (batch_id) DO NOTHING;

COMMIT;

-- Displays the published initial-batch status and watermarks.
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_end
FROM silver.ingestion_batch
WHERE load_type = 'INITIAL'
ORDER BY source_system_id;

-- <<< END SOURCE FILE: sql/module1_hongfei/03_load_initial_bronze.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/04_create_incremental_procedure.sql

-- Creates the reusable incremental CDC process, including validation, failure logging and watermark control.

-- Counts all raw business records retained in Bronze for one batch.
CREATE OR REPLACE FUNCTION silver.count_bronze_batch_records(
  p_batch_id varchar
)
RETURNS integer
LANGUAGE sql
STABLE
AS $count_records$
  SELECT count(*)::integer
  FROM (
    SELECT 1 FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_rows;
$count_records$;

-- Marks a batch as failed without advancing its watermark and records a blocking quality issue.
CREATE OR REPLACE FUNCTION silver.record_load_failure(
  p_batch_id varchar,
  p_source_system_id varchar,
  p_rule_name varchar,
  p_error_message text
)
RETURNS void
LANGUAGE plpgsql
AS $record_failure$
DECLARE
  v_issue_id varchar(50);
  v_version_reference varchar(150);
BEGIN
  UPDATE silver.ingestion_batch
  SET
    completed_at = clock_timestamp(),
    load_status = 'FAILED',
    records_processed = 0,
    watermark_end = NULL
  WHERE batch_id = p_batch_id;

  SELECT COALESCE(watermark_end, 'UNKNOWN')
  INTO v_version_reference
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id;

  v_issue_id := 'DQ-LOAD-' || substr(
    md5(p_batch_id || ':' || p_rule_name),
    1,
    32
  );

  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id,
    batch_id,
    source_system_id,
    verification_case_id,
    validation_run_id,
    data_layer,
    entity_name,
    record_reference,
    record_version_reference,
    attribute_name,
    rule_name,
    rule_version,
    issue_type,
    issue_description,
    severity,
    detected_at,
    resolved_at,
    issue_status
  )
  VALUES (
    v_issue_id,
    p_batch_id,
    p_source_system_id,
    NULL,
    'LOAD-' || p_batch_id,
    'BRONZE',
    'CDC_CHANGE_EVENT',
    p_batch_id,
    v_version_reference,
    NULL,
    p_rule_name,
    '1.0',
    'LOAD_VALIDATION',
    left(p_error_message, 1000),
    'BLOCKING',
    clock_timestamp(),
    NULL,
    'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    resolved_at = NULL,
    issue_status = 'OPEN';
END;
$record_failure$;

-- Stages, validates and publishes one simulated CDC batch with safe retry behaviour.
CREATE OR REPLACE PROCEDURE silver.process_incremental_batch(
  p_batch_id varchar,
  p_force_failure boolean DEFAULT FALSE
)
LANGUAGE plpgsql
AS $process_batch$
DECLARE
  v_spec source_systems.ingestion_batch%ROWTYPE;
  v_existing_status varchar(30);
  v_previous_watermark varchar(150);
  v_raw_count integer;
  v_event_count integer;
  v_invalid_operation_count integer;
  v_source_mismatch_count integer;
  v_missing_reference_count integer;
  v_bad_sequence_count integer;
  v_error_message text;
BEGIN
  -- Loads the source batch specification and skips batches already committed successfully.
  SELECT *
  INTO v_spec
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown source batch: %', p_batch_id;
  END IF;

  IF v_spec.load_type <> 'SIMULATED_CDC' THEN
    RAISE EXCEPTION
      'Batch % has load_type %, expected SIMULATED_CDC',
      p_batch_id,
      v_spec.load_type;
  END IF;

  SELECT load_status
  INTO v_existing_status
  FROM silver.ingestion_batch
  WHERE batch_id = p_batch_id;

  IF v_existing_status = 'SUCCEEDED' THEN
    RAISE NOTICE 'Batch % already succeeded; no data or watermark changed', p_batch_id;
    RETURN;
  END IF;

  -- Reads the last committed watermark and initialises the Silver control row as RUNNING.
  SELECT watermark_end
  INTO v_previous_watermark
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = v_spec.source_system_id;

  INSERT INTO bronze.source_system
  SELECT *
  FROM source_systems.source_system
  WHERE source_system_id = v_spec.source_system_id
  ON CONFLICT (source_system_id) DO NOTHING;

  INSERT INTO silver.source_system (
    source_system_id,
    system_name,
    system_type,
    system_description,
    system_owner,
    active_flag
  )
  SELECT
    source_system_id,
    system_name,
    system_type,
    system_description,
    system_owner,
    active_flag
  FROM source_systems.source_system
  WHERE source_system_id = v_spec.source_system_id
  ON CONFLICT (source_system_id) DO UPDATE SET
    system_name = EXCLUDED.system_name,
    system_type = EXCLUDED.system_type,
    system_description = EXCLUDED.system_description,
    system_owner = EXCLUDED.system_owner,
    active_flag = EXCLUDED.active_flag;

  INSERT INTO silver.ingestion_batch (
    batch_id,
    source_system_id,
    load_type,
    started_at,
    completed_at,
    load_status,
    records_received,
    records_processed,
    watermark_start,
    watermark_end
  )
  VALUES (
    p_batch_id,
    v_spec.source_system_id,
    v_spec.load_type,
    clock_timestamp(),
    NULL,
    'RUNNING',
    v_spec.records_received,
    0,
    v_previous_watermark,
    NULL
  )
  ON CONFLICT (batch_id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    completed_at = NULL,
    load_status = 'RUNNING',
    records_received = EXCLUDED.records_received,
    records_processed = 0,
    watermark_start = EXCLUDED.watermark_start,
    watermark_end = NULL;

  -- Retains the batch controls, raw records and CDC events in Bronze before validation.
  INSERT INTO bronze.ingestion_batch
  SELECT *
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id
  ON CONFLICT (batch_id) DO NOTHING;

  INSERT INTO bronze.raw_crm_customer
  SELECT * FROM source_systems.raw_crm_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_lending_customer
  SELECT * FROM source_systems.raw_lending_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_aml_kyc_customer
  SELECT * FROM source_systems.raw_aml_kyc_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_banking_account_snapshot
  SELECT * FROM source_systems.raw_banking_account_snapshot WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_loan_snapshot
  SELECT * FROM source_systems.raw_loan_snapshot WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_account_transaction
  SELECT * FROM source_systems.raw_account_transaction WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_kyc_verification
  SELECT * FROM source_systems.raw_kyc_verification WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_aml_screening
  SELECT * FROM source_systems.raw_aml_screening WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.cdc_change_event
  SELECT *
  FROM source_systems.cdc_change_event
  WHERE batch_id = p_batch_id
  ON CONFLICT (change_event_id) DO NOTHING;

  -- Provides a controlled failure after staging to demonstrate Bronze retention and retry.
  IF p_force_failure THEN
    PERFORM silver.record_load_failure(
      p_batch_id,
      v_spec.source_system_id,
      'forced_failure_demo',
      'Intentional failure used to prove that Bronze is retained, the watermark does not advance and the batch can be retried.'
    );
    RAISE NOTICE 'Batch % intentionally failed after Bronze staging', p_batch_id;
    RETURN;
  END IF;

  BEGIN
    -- Validates row counts, operation codes, source ownership, payload references and event sequences.
    v_raw_count := silver.count_bronze_batch_records(p_batch_id);

    SELECT count(*)::integer
    INTO v_event_count
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id;

    SELECT count(*)::integer
    INTO v_invalid_operation_count
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id
      AND COALESCE(operation_type, '') NOT IN ('I', 'U', 'D');

    SELECT count(*)::integer
    INTO v_source_mismatch_count
    FROM (
      SELECT source_system_id
      FROM bronze.cdc_change_event
      WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
    ) batch_sources
    WHERE source_system_id IS DISTINCT FROM v_spec.source_system_id;

    SELECT count(*)::integer
    INTO v_missing_reference_count
    FROM bronze.cdc_change_event event_row
    WHERE event_row.batch_id = p_batch_id
      AND NOT EXISTS (
        SELECT 1
        FROM (
          SELECT bronze_record_reference FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
        ) raw_reference
        WHERE raw_reference.bronze_record_reference =
          event_row.change_payload::jsonb ->> 'bronze_record_reference'
      );

    WITH batch_sequence AS (
      SELECT
        source_system_id,
        source_entity_name,
        min(event_sequence) AS min_sequence,
        max(event_sequence) AS max_sequence,
        count(*) AS event_count,
        count(DISTINCT event_sequence) AS distinct_count
      FROM bronze.cdc_change_event
      WHERE batch_id = p_batch_id
      GROUP BY source_system_id, source_entity_name
    ),
    sequence_with_prior AS (
      SELECT
        batch_sequence.*,
        COALESCE((
          SELECT max(previous_event.event_sequence)
          FROM silver.cdc_change_event previous_event
          WHERE previous_event.source_system_id = batch_sequence.source_system_id
            AND previous_event.source_entity_name = batch_sequence.source_entity_name
        ), 0) AS prior_max_sequence
      FROM batch_sequence
    )
    SELECT count(*)::integer
    INTO v_bad_sequence_count
    FROM sequence_with_prior
    WHERE distinct_count <> event_count
       OR max_sequence - min_sequence + 1 <> event_count
       OR min_sequence <> prior_max_sequence + 1;

    -- Combines all validation failures into one batch-level error message.
    v_error_message := NULL;

    IF v_spec.watermark_start IS DISTINCT FROM v_previous_watermark THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format(
          'watermark_start %s does not match last successful watermark %s',
          COALESCE(v_spec.watermark_start, 'NULL'),
          COALESCE(v_previous_watermark, 'NULL')
        )
      );
    END IF;

    IF v_spec.watermark_end IS NULL THEN
      v_error_message := concat_ws('; ', v_error_message, 'watermark_end is missing');
    END IF;

    IF v_raw_count <> v_spec.records_received THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('expected %s raw rows but found %s', v_spec.records_received, v_raw_count)
      );
    END IF;

    IF v_event_count <> v_spec.records_received THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('expected %s CDC events but found %s', v_spec.records_received, v_event_count)
      );
    END IF;

    IF v_invalid_operation_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s CDC events have an invalid operation_type', v_invalid_operation_count)
      );
    END IF;

    IF v_source_mismatch_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s staged rows do not match the batch source system', v_source_mismatch_count)
      );
    END IF;

    IF v_missing_reference_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s CDC payload references cannot be found in Bronze', v_missing_reference_count)
      );
    END IF;

    IF v_bad_sequence_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s source/entity streams have invalid event sequencing', v_bad_sequence_count)
      );
    END IF;

    IF v_error_message IS NOT NULL THEN
      PERFORM silver.record_load_failure(
        p_batch_id,
        v_spec.source_system_id,
        'incremental_batch_validation',
        v_error_message
      );
      RAISE NOTICE 'Batch % failed validation: %', p_batch_id, v_error_message;
      RETURN;
    END IF;

    -- Publishes valid CDC events, commits the watermark and resolves earlier retryable issues.
    INSERT INTO silver.cdc_change_event (
      change_event_id,
      source_system_id,
      batch_id,
      source_entity_name,
      source_record_reference,
      source_version_reference,
      operation_type,
      event_sequence,
      source_change_time,
      captured_at,
      change_payload
    )
    SELECT
      change_event_id,
      source_system_id,
      batch_id,
      source_entity_name,
      source_record_reference,
      source_version_reference,
      operation_type,
      event_sequence,
      source_change_time,
      captured_at,
      change_payload
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id
    ORDER BY source_entity_name, event_sequence
    ON CONFLICT (change_event_id) DO NOTHING;

    UPDATE silver.ingestion_batch
    SET
      completed_at = clock_timestamp(),
      load_status = 'SUCCEEDED',
      records_processed = v_raw_count,
      watermark_end = v_spec.watermark_end
    WHERE batch_id = p_batch_id;

    UPDATE silver.data_quality_issue
    SET
      resolved_at = clock_timestamp(),
      issue_status = 'RESOLVED'
    WHERE batch_id = p_batch_id
      AND issue_type = 'LOAD_VALIDATION'
      AND issue_status = 'OPEN';

    RAISE NOTICE
      'Batch % succeeded: % records processed, watermark advanced to %',
      p_batch_id,
      v_raw_count,
      v_spec.watermark_end;
  EXCEPTION
    WHEN OTHERS THEN
      -- Converts unexpected runtime errors into the same failed-batch control state.
      GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
      PERFORM silver.record_load_failure(
        p_batch_id,
        v_spec.source_system_id,
        'incremental_runtime_error',
        v_error_message
      );
      RAISE NOTICE 'Batch % failed with runtime error: %', p_batch_id, v_error_message;
  END;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_incremental_batch(varchar, boolean) IS
  'Stages one simulated CDC batch in Bronze, validates it, publishes valid events to Silver and advances the watermark only after success.';

-- <<< END SOURCE FILE: sql/module1_hongfei/04_create_incremental_procedure.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/05_run_failure_retry_demo.sql

-- Demonstrates B2-CRM failure, retained Bronze data, retry and idempotency.

CALL silver.process_incremental_batch('B2-CRM', TRUE);

-- Shows the failed batch state, retained data and unchanged committed watermark.
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id = 'B2-CRM';

SELECT
  silver.count_bronze_batch_records('B2-CRM') AS retained_bronze_rows,
  (SELECT count(*) FROM bronze.cdc_change_event WHERE batch_id = 'B2-CRM')
    AS retained_cdc_events,
  (SELECT watermark_end
   FROM silver.vw_latest_successful_watermark
   WHERE source_system_id = 'CRM') AS committed_watermark_after_failure;

-- Retries the staged batch.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

-- Repeats the call to verify idempotency.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

-- Displays the successful final batch state and published CRM CDC events.
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id = 'B2-CRM';

SELECT
  count(*) AS silver_crm_cdc_events
FROM silver.cdc_change_event
WHERE batch_id = 'B2-CRM';

-- <<< END SOURCE FILE: sql/module1_hongfei/05_run_failure_retry_demo.sql

-- >>> BEGIN SOURCE FILE: sql/module1_hongfei/06_run_remaining_incremental_batches.sql

-- Processes the remaining incremental batches and displays their outcomes.

-- Runs the Lending batch and the deliberately invalid AML/KYC batch.
CALL silver.process_incremental_batch('B2-LEND', FALSE);
CALL silver.process_incremental_batch('B2-AMLKYC', FALSE);

-- Displays the final control state and watermark outcome for both batches.
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id IN ('B2-LEND', 'B2-AMLKYC')
ORDER BY batch_id;

-- Displays the blocking quality issue created for the failed AML/KYC batch.
SELECT
  data_quality_issue_id,
  batch_id,
  rule_name,
  issue_description,
  severity,
  issue_status
FROM silver.data_quality_issue
WHERE batch_id = 'B2-AMLKYC'
  AND issue_type = 'LOAD_VALIDATION'
ORDER BY detected_at DESC;

-- <<< END SOURCE FILE: sql/module1_hongfei/06_run_remaining_incremental_batches.sql

-- >>> BEGIN SOURCE FILE: sql/module2_mina/01_standardise_source_customer_records.sql

-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 1: Move successful Bronze customer records into Silver

BEGIN;

-- Combine the three Bronze customer tables
-- Only successful ingestion batches are used
CREATE OR REPLACE VIEW silver.v_member2_bronze_customer_versions AS
SELECT c.*
FROM bronze.raw_crm_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED'

UNION ALL

SELECT c.*
FROM bronze.raw_lending_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED'

UNION ALL

SELECT c.*
FROM bronze.raw_aml_kyc_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED';


-- LEAD finds when the next version of the same source customer starts
WITH customer_versions AS (
    SELECT
        v.*,
        COALESCE(v.source_last_updated_at, v.ingested_at) AS valid_from_time,

        LEAD(COALESCE(v.source_last_updated_at, v.ingested_at)) OVER (
            PARTITION BY v.source_system_id, v.source_customer_reference
            ORDER BY v.source_record_version
        ) AS next_version_time

    FROM silver.v_member2_bronze_customer_versions v
)

INSERT INTO silver.source_customer_record (
    source_customer_record_id,
    source_system_id,
    batch_id,
    source_customer_reference,
    source_record_version,
    bronze_record_reference,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,
    source_last_updated_at,
    valid_from,
    valid_to,
    is_current_version,
    record_hash
)

SELECT
    -- Stable ID for each source record version
    'SCR-' || source_system_id || '-' ||
    source_customer_reference || '-V' ||
    source_record_version::text,

    source_system_id,
    batch_id,
    source_customer_reference,
    source_record_version,
    bronze_record_reference,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,
    source_last_updated_at,
    valid_from_time,

    -- A delete is closed immediately
    -- Other old versions close when the next version starts
    CASE
        WHEN operation_type = 'D' THEN valid_from_time
        ELSE next_version_time
    END,

    -- Only the latest non-deleted version is current.
    (
        next_version_time IS NULL
        AND operation_type <> 'D'
        AND UPPER(COALESCE(record_status, '')) <> 'DELETED'
    ),

    -- Hash kept for traceability and change checking.
    MD5(
        CONCAT_WS(
            '|',
            source_system_id,
            source_customer_reference,
            source_record_version::text,
            COALESCE(source_full_name, ''),
            COALESCE(source_date_of_birth::text, ''),
            COALESCE(source_email_address, ''),
            COALESCE(source_phone_number, ''),
            COALESCE(source_address, ''),
            COALESCE(record_status, '')
        )
    )

FROM customer_versions

-- If this source version already exists, update it instead of duplicating it
ON CONFLICT (source_customer_record_id) DO UPDATE
SET
    batch_id                   = EXCLUDED.batch_id,
    bronze_record_reference    = EXCLUDED.bronze_record_reference,
    source_full_name           = EXCLUDED.source_full_name,
    source_date_of_birth       = EXCLUDED.source_date_of_birth,
    source_email_address       = EXCLUDED.source_email_address,
    source_phone_number        = EXCLUDED.source_phone_number,
    source_address             = EXCLUDED.source_address,
    source_last_updated_at     = EXCLUDED.source_last_updated_at,
    valid_from                 = EXCLUDED.valid_from,
    valid_to                   = EXCLUDED.valid_to,
    is_current_version         = EXCLUDED.is_current_version,
    record_hash                = EXCLUDED.record_hash;

COMMIT;

-- check
SELECT
    source_system_id,
    source_customer_reference,
    source_record_version,
    is_current_version
FROM silver.source_customer_record
ORDER BY source_system_id, source_customer_reference, source_record_version;

-- <<< END SOURCE FILE: sql/module2_mina/01_standardise_source_customer_records.sql

-- >>> BEGIN SOURCE FILE: sql/module2_mina/02_prepare_matching_candidates.sql

-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 2: Clean matching fields and create candidate pairs

-- The original source values stay unchanged
-- This view only creates standardised values for matching
CREATE OR REPLACE VIEW silver.v_member2_matching_input AS
WITH cleaned AS (
    SELECT
        scr.*,

        -- Remove spaces, brackets, + signs and other phone formatting
        REGEXP_REPLACE(
            COALESCE(scr.source_phone_number, ''),
            '[^0-9]',
            '',
            'g'
        ) AS phone_digits

    FROM silver.source_customer_record scr
    WHERE scr.is_current_version = TRUE
)

SELECT
    source_customer_record_id,
    source_system_id,
    source_customer_reference,
    source_record_version,

    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,

    -- Standardise names
    -- Example: "WONG, ALICE" becomes "ALICE WONG".
    NULLIF(
        UPPER(
            TRIM(
                CASE
                    WHEN POSITION(',' IN COALESCE(source_full_name, '')) > 0
                    THEN
                        SPLIT_PART(source_full_name, ',', 2)
                        || ' ' ||
                        SPLIT_PART(source_full_name, ',', 1)
                    ELSE source_full_name
                END
            )
        ),
        ''
    ) AS norm_name,

    source_date_of_birth AS norm_dob,

    -- LOWER(TRIM(email))
    NULLIF(
        LOWER(TRIM(COALESCE(source_email_address, ''))),
        ''
    ) AS norm_email,

    -- Convert Australian 04xx and +61 4xx formats to the same digits
    NULLIF(
        CASE
            WHEN phone_digits ~ '^61[0-9]{9}$'
                THEN SUBSTRING(phone_digits FROM 3)
            WHEN phone_digits ~ '^0[0-9]{9}$'
                THEN SUBSTRING(phone_digits FROM 2)
            ELSE phone_digits
        END,
        ''
    ) AS norm_phone,

    -- Standardise address text
    NULLIF(
        REGEXP_REPLACE(
            UPPER(TRIM(COALESCE(source_address, ''))),
            '[^A-Z0-9 ]',
            '',
            'g'
        ),
        ''
    ) AS norm_address

FROM cleaned;

-- Compare customers only across different source systems
-- a.id < b.id prevents the same pair appearing twice
CREATE OR REPLACE VIEW silver.v_member2_match_candidates AS
SELECT
    a.source_customer_record_id AS record_a_id,
    a.source_system_id AS source_a,
    a.source_customer_reference AS source_ref_a,

    b.source_customer_record_id AS record_b_id,
    b.source_system_id AS source_b,
    b.source_customer_reference AS source_ref_b,

    (a.norm_name IS NOT NULL
     AND b.norm_name IS NOT NULL
     AND a.norm_name = b.norm_name) AS name_match,

    (a.norm_dob IS NOT NULL
     AND b.norm_dob IS NOT NULL
     AND a.norm_dob = b.norm_dob) AS dob_match,

    (a.norm_dob IS NOT NULL
     AND b.norm_dob IS NOT NULL
     AND a.norm_dob <> b.norm_dob) AS dob_conflict,

    (a.norm_email IS NOT NULL
     AND b.norm_email IS NOT NULL
     AND a.norm_email = b.norm_email) AS email_match,

    (a.norm_phone IS NOT NULL
     AND b.norm_phone IS NOT NULL
     AND a.norm_phone = b.norm_phone) AS phone_match,

    (a.norm_address IS NOT NULL
     AND b.norm_address IS NOT NULL
     AND a.norm_address = b.norm_address) AS address_match

FROM silver.v_member2_matching_input a
JOIN silver.v_member2_matching_input b
  ON a.source_customer_record_id < b.source_customer_record_id
 AND a.source_system_id <> b.source_system_id

-- Keep only pairs with at least one matching field
WHERE
       (a.norm_name IS NOT NULL AND a.norm_name = b.norm_name)
    OR (a.norm_dob IS NOT NULL AND a.norm_dob = b.norm_dob)
    OR (a.norm_email IS NOT NULL AND a.norm_email = b.norm_email)
    OR (a.norm_phone IS NOT NULL AND a.norm_phone = b.norm_phone)
    OR (a.norm_address IS NOT NULL AND a.norm_address = b.norm_address);

-- check
SELECT *
FROM silver.v_member2_match_candidates
ORDER BY source_ref_a, source_ref_b;

-- <<< END SOURCE FILE: sql/module2_mina/02_prepare_matching_candidates.sql

-- >>> BEGIN SOURCE FILE: sql/module2_mina/03_apply_matching_rules.sql

-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 3: Apply simple deterministic matching rules

CREATE OR REPLACE VIEW silver.v_member2_pair_decisions AS
SELECT
    c.*,

    -- The conflict rule is checked first
    CASE
        WHEN dob_conflict AND name_match AND phone_match
            THEN 'PENDING_REVIEW'

        WHEN dob_match AND email_match AND phone_match
            THEN 'ACCEPTED'

        WHEN dob_match AND email_match
            THEN 'ACCEPTED'

        WHEN dob_match AND phone_match
            THEN 'ACCEPTED'

        WHEN dob_match AND name_match AND address_match
            THEN 'ACCEPTED'

        ELSE 'NO_MATCH'
    END AS pair_decision,

    CASE
        WHEN dob_conflict AND name_match AND phone_match THEN 0.7000
        WHEN dob_match AND email_match AND phone_match   THEN 0.9900
        WHEN dob_match AND email_match                   THEN 0.9700
        WHEN dob_match AND phone_match                   THEN 0.9700
        WHEN dob_match AND name_match AND address_match  THEN 0.9200
        ELSE 0.0000
    END::decimal(5,4) AS pair_confidence_score,

    -- Save the rule so the decision can be explained later
    CASE
        WHEN dob_conflict AND name_match AND phone_match
            THEN 'DOB_CONFLICT_NAME_PHONE_MATCH'
        WHEN dob_match AND email_match AND phone_match
            THEN 'DOB_EMAIL_PHONE_EXACT'
        WHEN dob_match AND email_match
            THEN 'DOB_EMAIL_EXACT'
        WHEN dob_match AND phone_match
            THEN 'DOB_PHONE_EXACT'
        WHEN dob_match AND name_match AND address_match
            THEN 'DOB_NAME_ADDRESS_EXACT'
        ELSE 'NO_MATCH_RULE'
    END AS pair_match_rule

FROM silver.v_member2_match_candidates c;

-- Show only decisions that need action
SELECT
    source_a,
    source_ref_a,
    source_b,
    source_ref_b,
    pair_decision,
    pair_confidence_score,
    pair_match_rule
FROM silver.v_member2_pair_decisions
WHERE pair_decision <> 'NO_MATCH'
ORDER BY source_ref_a, source_ref_b;

-- <<< END SOURCE FILE: sql/module2_mina/03_apply_matching_rules.sql

-- >>> BEGIN SOURCE FILE: sql/module2_mina/04_assign_unified_customers.sql

-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 4: Assign one customer ID to accepted source records

BEGIN;

-- Close matches that belong to an old source record version
UPDATE silver.customer_source_match m
SET
    effective_to = CURRENT_TIMESTAMP,
    is_current_match = FALSE
FROM silver.source_customer_record scr
WHERE m.source_customer_record_id = scr.source_customer_record_id
  AND m.is_current_match = TRUE
  AND scr.is_current_version = FALSE;

-- Rebuild current decisions for current source records
UPDATE silver.customer_source_match m
SET
    effective_to = CURRENT_TIMESTAMP,
    is_current_match = FALSE
WHERE m.is_current_match = TRUE
  AND EXISTS (
      SELECT 1
      FROM silver.v_member2_matching_input i
      WHERE i.source_customer_record_id = m.source_customer_record_id
  );

-- 1. Find records that need manual review
-- Source priority is used only to choose which side is held back
-- CRM = 1, AML/KYC = 2, Lending = 3
DROP TABLE IF EXISTS tmp_member2_pending;

CREATE TEMP TABLE tmp_member2_pending AS
WITH pending_candidates AS (
    SELECT
        CASE
            WHEN
                CASE source_a
                    WHEN 'CRM' THEN 1
                    WHEN 'AMLKYC' THEN 2
                    WHEN 'LEND' THEN 3
                    ELSE 9
                END
                >
                CASE source_b
                    WHEN 'CRM' THEN 1
                    WHEN 'AMLKYC' THEN 2
                    WHEN 'LEND' THEN 3
                    ELSE 9
                END
            THEN record_a_id
            ELSE record_b_id
        END AS source_customer_record_id,

        pair_confidence_score,
        pair_match_rule

    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'PENDING_REVIEW'
)

SELECT
    source_customer_record_id,
    MAX(pair_confidence_score) AS match_confidence_score,
    MIN(pair_match_rule) AS match_rule
FROM pending_candidates
GROUP BY source_customer_record_id;

-- 2. Build a simple group for accepted records
-- Each accepted pair links two source records
-- For the supplied three-source prototype, all sources are directly compared, so MIN(record_id) gives the same group key to matching rows
-- Single source customers simply keep their own record ID as the key
DROP TABLE IF EXISTS tmp_member2_assignment;

CREATE TEMP TABLE tmp_member2_assignment AS
WITH eligible_records AS (
    SELECT i.*
    FROM silver.v_member2_matching_input i
    WHERE NOT EXISTS (
        SELECT 1
        FROM tmp_member2_pending p
        WHERE p.source_customer_record_id = i.source_customer_record_id
    )
),

group_options AS (
    -- Every record can use itself as a group key
    SELECT
        source_customer_record_id AS record_id,
        source_customer_record_id AS group_key
    FROM eligible_records

    UNION ALL

    -- Accepted link: A can also use B as a group key
    SELECT
        d.record_a_id,
        d.record_b_id
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'

    UNION ALL

    -- Accepted link: B can also use A as a group key
    SELECT
        d.record_b_id,
        d.record_a_id
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'
),

customer_groups AS (
    SELECT
        record_id,
        MIN(group_key) AS group_key
    FROM group_options
    GROUP BY record_id
)

SELECT
    e.source_customer_record_id,

    -- Stable enterprise customer ID for the group
    'CUST-' ||
    UPPER(
        SUBSTRING(
            MD5(g.group_key)
            FROM 1 FOR 12
        )
    ) AS customer_id

FROM eligible_records e
JOIN customer_groups g
  ON e.source_customer_record_id = g.record_id;

-- 3. Create customer_master shells
-- Module 3 will  choose the authoritative name, DOB, email, phone and address. ON CONFLICT prevents this script from replacing Module 3's existing golden customer values
INSERT INTO silver.customer_master (
    customer_id,
    customer_full_name,
    date_of_birth,
    email_address,
    phone_number,
    residential_address,
    suburb_city,
    state_region,
    postcode,
    country_code,
    customer_status,
    customer_since_date,
    created_at,
    last_updated_at
)

SELECT DISTINCT
    customer_id,
    'PENDING SURVIVORSHIP'::varchar(150),
    NULL::date,
    NULL::varchar(150),
    NULL::varchar(50),
    NULL::varchar(255),
    NULL::varchar(100),
    NULL::varchar(100),
    NULL::varchar(20),
    NULL::varchar(3),
    'PENDING_SURVIVORSHIP'::varchar(30),
    NULL::date,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP

FROM tmp_member2_assignment

ON CONFLICT (customer_id) DO NOTHING;

-- 4. Collect the best matching evidence for each accepted record
DROP TABLE IF EXISTS tmp_member2_evidence;

CREATE TEMP TABLE tmp_member2_evidence AS
WITH evidence AS (
    SELECT
        record_a_id AS source_customer_record_id,
        pair_confidence_score,
        pair_match_rule
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'

    UNION ALL

    SELECT
        record_b_id,
        pair_confidence_score,
        pair_match_rule
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
)

SELECT
    source_customer_record_id,
    MAX(pair_confidence_score) AS match_confidence_score,
    MIN(pair_match_rule) AS match_rule
FROM evidence
GROUP BY source_customer_record_id;

-- 5. Save accepted and pending review decisions
INSERT INTO silver.customer_source_match (
    match_id,
    source_customer_record_id,
    customer_id,
    reviewed_by_user_id,
    match_status,
    match_confidence_score,
    match_rule,
    manual_review_flag,
    effective_from,
    effective_to,
    is_current_match,
    matched_at
)

-- Accepted records
SELECT
    'MATCH-' ||
    UPPER(
        SUBSTRING(
            MD5(
                a.source_customer_record_id
                || '|ACCEPTED|'
                || a.customer_id
            )
            FROM 1 FOR 12
        )
    ),

    a.source_customer_record_id,
    a.customer_id,
    NULL::varchar(50),
    'ACCEPTED',

    COALESCE(
        e.match_confidence_score,
        1.0000::decimal(5,4)
    ),

    COALESCE(
        e.match_rule,
        'NEW_CUSTOMER_SINGLE_SOURCE'
    ),

    FALSE,
    CURRENT_TIMESTAMP,
    NULL::timestamp,
    TRUE,
    CURRENT_TIMESTAMP

FROM tmp_member2_assignment a
LEFT JOIN tmp_member2_evidence e
  ON a.source_customer_record_id = e.source_customer_record_id

UNION ALL

-- Records that need manual review
SELECT
    'MATCH-' ||
    UPPER(
        SUBSTRING(
            MD5(
                p.source_customer_record_id
                || '|PENDING_REVIEW|'
                || p.match_rule
            )
            FROM 1 FOR 12
        )
    ),

    p.source_customer_record_id,
    NULL::varchar(50),
    NULL::varchar(50),
    'PENDING_REVIEW',
    p.match_confidence_score,
    p.match_rule,
    TRUE,
    CURRENT_TIMESTAMP,
    NULL::timestamp,
    TRUE,
    CURRENT_TIMESTAMP

FROM tmp_member2_pending p

-- Rerunning the script updates the same decision instead of duplicating it
ON CONFLICT (match_id) DO UPDATE
SET
    customer_id = EXCLUDED.customer_id,
    match_status = EXCLUDED.match_status,
    match_confidence_score = EXCLUDED.match_confidence_score,
    match_rule = EXCLUDED.match_rule,
    manual_review_flag = EXCLUDED.manual_review_flag,
    effective_to = NULL,
    is_current_match = TRUE,
    matched_at = CURRENT_TIMESTAMP;

COMMIT;

-- check
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
ORDER BY scr.source_system_id, scr.source_customer_reference;

-- <<< END SOURCE FILE: sql/module2_mina/04_assign_unified_customers.sql

-- >>> BEGIN SOURCE FILE: sql/module3_kaijie/01_prepare_survivorship_candidates.sql

-- PostgreSQL 15+. Install after shared setup and Member 2 scripts 01-04.
-- Prototype policy v1: source preference is NOT evidence of KYC verification.
BEGIN;
CREATE OR REPLACE VIEW silver.v_member3_attribute_candidates AS
WITH eligible AS (
  SELECT m.customer_id, m.match_id, s.*
  FROM silver.customer_source_match m
  JOIN silver.source_customer_record s USING (source_customer_record_id)
  JOIN silver.ingestion_batch b ON b.batch_id = s.batch_id
    AND b.source_system_id = s.source_system_id
  WHERE m.match_status = 'ACCEPTED' AND m.is_current_match
    AND m.effective_to IS NULL AND m.customer_id IS NOT NULL
    AND s.is_current_version AND s.valid_to IS NULL
    AND b.load_status = 'SUCCEEDED'
), values_by_attribute AS (
  SELECT e.*, a.attribute_name, a.source_attribute_name,
    a.raw_value, NULLIF(btrim(a.raw_value), '') AS selected_value,
    a.attribute_name IN ('email_address', 'phone_number') AS latest_first
  FROM eligible e
  CROSS JOIN LATERAL (VALUES
    ('customer_full_name', 'source_full_name', e.source_full_name::text),
    ('date_of_birth', 'source_date_of_birth', e.source_date_of_birth::text),
    ('email_address', 'source_email_address', e.source_email_address::text),
    ('phone_number', 'source_phone_number', e.source_phone_number::text),
    ('residential_address', 'source_address', e.source_address::text)
  ) a(attribute_name, source_attribute_name, raw_value)
), priorities AS (
  SELECT v.*,
    CASE WHEN latest_first THEN
      CASE source_system_id WHEN 'CRM' THEN 1 WHEN 'AMLKYC' THEN 2 WHEN 'LEND' THEN 3 ELSE 9 END
    ELSE
      CASE source_system_id WHEN 'AMLKYC' THEN 1 WHEN 'CRM' THEN 2 WHEN 'LEND' THEN 3 ELSE 9 END
    END AS source_priority,
    CASE WHEN latest_first
      THEN 'v1: latest nonblank; tie CRM>AMLKYC>LEND; stable source ID'
      ELSE 'v1: nonblank AMLKYC>CRM>LEND; newest within priority; stable source ID'
    END::varchar(200) AS survivorship_rule
  FROM values_by_attribute v WHERE selected_value IS NOT NULL
)
SELECT p.*, row_number() OVER (
  PARTITION BY customer_id, attribute_name
  ORDER BY
    CASE WHEN latest_first THEN source_last_updated_at END DESC NULLS LAST,
    source_priority,
    source_last_updated_at DESC NULLS LAST,
    source_system_id, source_customer_reference, source_record_version DESC,
    source_customer_record_id, match_id
) AS candidate_rank
FROM priorities p;

-- Enforce this invariant rather than relying only on a table comment.
-- Existing duplicate current selections cause installation to fail visibly.
CREATE UNIQUE INDEX IF NOT EXISTS member3_one_current_attribute
  ON silver.customer_attribute_source(customer_id, attribute_name) WHERE is_current;
COMMIT;

-- <<< END SOURCE FILE: sql/module3_kaijie/01_prepare_survivorship_candidates.sql

-- >>> BEGIN SOURCE FILE: sql/module3_kaijie/02_apply_survivorship.sql

-- Install the procedure, then CALL it separately (see README).
-- Processing-time history: never backdate a decision to the source timestamp.
CREATE OR REPLACE PROCEDURE silver.apply_member3_survivorship()
LANGUAGE plpgsql AS $procedure$
DECLARE
  c record; a record; winner record; previous record;
  old_value text; new_value text; chosen_id varchar(50);
  has_winner boolean; has_previous boolean; selection_changed boolean;
  run_at timestamp; run_id text; event_id text; next_status text;
BEGIN
  -- Serialise with source/matching writers for a consistent input snapshot.
  LOCK TABLE silver.customer_master, silver.source_customer_record,
    silver.customer_source_match, silver.ingestion_batch,
    silver.customer_attribute_source, silver.customer_history,
    silver.data_lineage_record IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (
    SELECT 1 FROM silver.customer_source_match m
    JOIN silver.source_customer_record s USING(source_customer_record_id)
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
    GROUP BY s.source_system_id, s.source_customer_reference HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'More than one current accepted match per source identity'; END IF;
  IF EXISTS (
    SELECT 1 FROM silver.customer_source_match m
    JOIN silver.source_customer_record s USING(source_customer_record_id)
    JOIN silver.ingestion_batch b ON b.batch_id = s.batch_id
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
      AND (m.customer_id IS NULL OR m.effective_to IS NOT NULL
        OR NOT s.is_current_version OR s.valid_to IS NOT NULL
        OR b.load_status <> 'SUCCEEDED' OR b.source_system_id <> s.source_system_id)
  ) THEN RAISE EXCEPTION 'Accepted matching input is inconsistent; rerun/fix Member 2 first'; END IF;

  run_at := greatest(clock_timestamp()::timestamp,
    coalesce((SELECT max(effective_from) + interval '1 microsecond'
              FROM silver.customer_attribute_source), '-infinity'::timestamp),
    coalesce((SELECT max(effective_from) + interval '1 microsecond'
              FROM silver.customer_history), '-infinity'::timestamp));
  run_id := 'M3-' || md5(run_at::text);

  FOR c IN
    SELECT cm.* FROM silver.customer_master cm
    WHERE cm.customer_status = 'PENDING_SURVIVORSHIP'
      OR EXISTS (SELECT 1 FROM silver.customer_source_match m
        WHERE m.customer_id = cm.customer_id AND m.is_current_match AND m.match_status = 'ACCEPTED')
      OR EXISTS (SELECT 1 FROM silver.customer_attribute_source p
        WHERE p.customer_id = cm.customer_id AND p.survivorship_rule LIKE 'v1:%')
    ORDER BY cm.customer_id
  LOOP
    FOR a IN SELECT * FROM (VALUES
      ('customer_full_name'), ('date_of_birth'), ('email_address'),
      ('phone_number'), ('residential_address')) attrs(attribute_name)
    LOOP
      SELECT * INTO winner FROM silver.v_member3_attribute_candidates
        WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND candidate_rank = 1;
      has_winner := FOUND;
      SELECT * INTO previous FROM silver.customer_attribute_source
        WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND is_current;
      has_previous := FOUND;
      old_value := to_jsonb(c) ->> a.attribute_name;

      IF NOT has_winner THEN
        -- Retain the last known master value, but do NOT claim its old source
        -- is still current. Its historical selection and lineage remain.
        IF has_previous THEN
          UPDATE silver.customer_attribute_source SET effective_to = run_at, is_current = FALSE
            WHERE attribute_source_id = previous.attribute_source_id;
          UPDATE silver.customer_master SET last_updated_at = run_at WHERE customer_id = c.customer_id;
          event_id := 'LIN-' || md5(run_id || previous.attribute_source_id || '|withdraw');
          INSERT INTO silver.data_lineage_record (
            lineage_id, transformation_run_id, source_layer, source_entity_name,
            source_record_reference, source_version_reference, source_attribute_name,
            source_record_snapshot, target_layer, target_entity_name,
            target_record_reference, target_version_reference, target_attribute_name,
            target_record_snapshot, transformation_name, transformation_version, transformation_timestamp
          ) VALUES (
            event_id, run_id, 'silver', 'customer_attribute_source', previous.attribute_source_id,
            previous.effective_from::text, a.attribute_name, to_jsonb(previous)::text,
            'silver', 'customer_master', c.customer_id, run_id, a.attribute_name,
            jsonb_build_object('retained_value', old_value, 'current_source', NULL,
              'reason', 'No eligible nonblank source; last known value retained')::text,
            'member3_withdraw_current_source', 'v1', run_at
          );
        END IF;
        CONTINUE;
      END IF;

      new_value := winner.selected_value;
      selection_changed := NOT has_previous;
      IF has_previous THEN
        selection_changed := previous.match_id IS DISTINCT FROM winner.match_id
          OR previous.selected_value IS DISTINCT FROM new_value
          OR previous.survivorship_rule IS DISTINCT FROM winner.survivorship_rule;
      END IF;
      IF NOT selection_changed AND old_value IS NOT DISTINCT FROM new_value THEN CONTINUE; END IF;

      IF selection_changed THEN
        IF has_previous THEN
          UPDATE silver.customer_attribute_source SET effective_to = run_at, is_current = FALSE
            WHERE attribute_source_id = previous.attribute_source_id;
        END IF;
        chosen_id := 'AS-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name);
        INSERT INTO silver.customer_attribute_source VALUES (
          chosen_id, c.customer_id, winner.match_id, a.attribute_name, new_value,
          winner.survivorship_rule, run_at, NULL, TRUE
        );
      ELSE chosen_id := previous.attribute_source_id;
      END IF;

      IF old_value IS DISTINCT FROM new_value THEN
        -- Half-open periods [from,to) describe when new_value was the master value.
        UPDATE silver.customer_history SET effective_to = run_at
          WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND effective_to IS NULL;
        INSERT INTO silver.customer_history VALUES (
          'HIST-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name),
          c.customer_id, chosen_id, a.attribute_name, old_value, new_value,
          run_at, NULL,
          CASE WHEN c.customer_status = 'PENDING_SURVIVORSHIP' AND NOT has_previous
            THEN 'INITIAL_SELECTION: ' ELSE 'VALUE_CHANGE: ' END || winner.survivorship_rule
        );
        IF a.attribute_name = 'date_of_birth' THEN
          UPDATE silver.customer_master SET date_of_birth = new_value::date, last_updated_at = run_at
            WHERE customer_id = c.customer_id;
        ELSE
          EXECUTE format('UPDATE silver.customer_master SET %I = $1, last_updated_at = $2 WHERE customer_id = $3', a.attribute_name)
            USING new_value, run_at, c.customer_id;
        END IF;
      ELSE
        UPDATE silver.customer_master SET last_updated_at = run_at WHERE customer_id = c.customer_id;
      END IF;

      INSERT INTO silver.data_lineage_record (
        lineage_id, batch_id, source_system_id, transformation_run_id,
        source_layer, source_entity_name, source_record_reference, source_version_reference,
        source_attribute_name, source_record_snapshot, target_layer, target_entity_name,
        target_record_reference, target_version_reference, target_attribute_name,
        target_record_snapshot, transformation_name, transformation_version, transformation_timestamp
      ) VALUES (
        'LIN-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name),
        winner.batch_id, winner.source_system_id, run_id, 'silver', 'source_customer_record',
        winner.source_customer_record_id, winner.source_record_version::text,
        winner.source_attribute_name,
        jsonb_build_object('raw_value', winner.raw_value, 'match_id', winner.match_id,
          'bronze_record_reference', winner.bronze_record_reference,
          'source_last_updated_at', winner.source_last_updated_at)::text,
        'silver', 'customer_master', c.customer_id, run_id, a.attribute_name,
        jsonb_build_object('selected_value', new_value, 'previous_value', old_value,
          'attribute_source_id', chosen_id, 'rule', winner.survivorship_rule)::text,
        'member3_attribute_survivorship', 'v1', run_at
      );
    END LOOP;

    -- This is integration status, not a KYC verdict or bank account status.
    next_status := CASE
      WHEN NOT EXISTS (SELECT 1 FROM silver.customer_source_match m
        WHERE m.customer_id = c.customer_id AND m.match_status = 'ACCEPTED' AND m.is_current_match)
        THEN 'NO_CURRENT_SOURCE'
      WHEN EXISTS (SELECT 1 FROM silver.v_member3_attribute_candidates v
        WHERE v.customer_id = c.customer_id AND v.attribute_name = 'customer_full_name') THEN 'ACTIVE'
      ELSE 'PENDING_SURVIVORSHIP' END;
    IF c.customer_status IS DISTINCT FROM next_status THEN
      INSERT INTO silver.customer_history VALUES (
        'HIST-' || md5(run_id || '|' || c.customer_id || '|customer_status'),
        c.customer_id, NULL, 'customer_status', c.customer_status, next_status, run_at, NULL,
        'DERIVED_STATUS: v1 current accepted sources and available name; not a compliance verdict'
      );
      UPDATE silver.customer_history SET effective_to = run_at
        WHERE customer_id = c.customer_id AND attribute_name = 'customer_status'
          AND effective_to IS NULL AND effective_from < run_at;
      INSERT INTO silver.data_lineage_record (
        lineage_id, transformation_run_id, source_layer, source_entity_name,
        source_record_reference, source_version_reference, source_record_snapshot,
        target_layer, target_entity_name, target_record_reference, target_version_reference,
        target_attribute_name, target_record_snapshot, transformation_name,
        transformation_version, transformation_timestamp
      ) VALUES (
        'LIN-' || md5(run_id || '|' || c.customer_id || '|customer_status'), run_id,
        'silver', 'customer_master', c.customer_id, c.last_updated_at::text,
        jsonb_build_object('previous_master', to_jsonb(c), 'decision_context',
          (SELECT coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) FROM silver.customer_source_match m
            WHERE m.customer_id = c.customer_id), 'has_nonblank_name',
          EXISTS (SELECT 1 FROM silver.v_member3_attribute_candidates v
            WHERE v.customer_id = c.customer_id AND v.attribute_name = 'customer_full_name'))::text,
        'silver', 'customer_master', c.customer_id, run_id, 'customer_status',
        jsonb_build_object('old_value', c.customer_status, 'new_value', next_status)::text,
        'member3_derived_integration_status', 'v1', run_at
      );
      UPDATE silver.customer_master SET customer_status = next_status, last_updated_at = run_at
        WHERE customer_id = c.customer_id;
    END IF;
  END LOOP;
END;
$procedure$;

-- Execute separately after installing this file:
-- CALL silver.apply_member3_survivorship();

-- <<< END SOURCE FILE: sql/module3_kaijie/02_apply_survivorship.sql

-- >>> BEGIN GENERATED SECTION: Member 3 integration call

-- Build the golden customer record before downstream dimensions and facts.
CALL silver.apply_member3_survivorship();

-- <<< END GENERATED SECTION: Member 3 integration call

-- >>> BEGIN SOURCE FILE: sql/module4_dan/01_load_silver_financials.sql

-- Step 1: Load accounts, loans and transactions from Bronze into Silver.
-- Run: CALL silver.load_financials(DATE '2026-09-15');
BEGIN;

-- Load one reporting date of financial data into Silver.
CREATE OR REPLACE PROCEDURE silver.load_financials(p_date date)
LANGUAGE plpgsql AS $$
DECLARE
  v_run text := 'FIN-' || p_date;
BEGIN
  -- Stop if Silver already has a later date.
  IF EXISTS (SELECT 1 FROM silver.banking_account WHERE as_of_date > p_date)
     OR EXISTS (SELECT 1 FROM silver.loan WHERE as_of_date > p_date) THEN
    RAISE EXCEPTION 'Silver already holds data after %; earlier dates cannot be reloaded', p_date;
  END IF;

  -- Clear old issues from the last run of this date.
  DELETE FROM silver.data_quality_issue WHERE validation_run_id = v_run;

  -- Get the latest version of each account and its matched customer_id.
  DROP TABLE IF EXISTS tmp_account;
  CREATE TEMP TABLE tmp_account ON COMMIT DROP AS
  SELECT DISTINCT ON (r.source_system_id, r.source_account_reference)
         r.*, m.customer_id
  FROM bronze.raw_banking_account_snapshot r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  LEFT JOIN silver.source_customer_record s
    ON s.source_system_id = r.source_system_id
   AND s.source_customer_reference = r.source_customer_reference
   AND s.is_current_version
  LEFT JOIN silver.customer_source_match m
    ON m.source_customer_record_id = s.source_customer_record_id
   AND m.is_current_match AND m.match_status = 'ACCEPTED'
  WHERE r.as_of_date <= p_date
  ORDER BY r.source_system_id, r.source_account_reference, r.source_record_version DESC;

  -- Get the latest version of each loan and its matched customer_id.
  DROP TABLE IF EXISTS tmp_loan;
  CREATE TEMP TABLE tmp_loan ON COMMIT DROP AS
  SELECT DISTINCT ON (r.source_system_id, r.source_loan_reference)
         r.*, m.customer_id
  FROM bronze.raw_loan_snapshot r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  LEFT JOIN silver.source_customer_record s
    ON s.source_system_id = r.source_system_id
   AND s.source_customer_reference = r.source_customer_reference
   AND s.is_current_version
  LEFT JOIN silver.customer_source_match m
    ON m.source_customer_record_id = s.source_customer_record_id
   AND m.is_current_match AND m.match_status = 'ACCEPTED'
  WHERE r.as_of_date <= p_date
  ORDER BY r.source_system_id, r.source_loan_reference, r.source_record_version DESC;

  -- Log rows that cannot be loaded (no customer match, non-AUD, delete).
  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, validation_run_id, data_layer, entity_name, record_reference,
    record_version_reference, rule_name, rule_version, issue_type, issue_description,
    severity, detected_at, issue_status)
  SELECT left('FIN-' || md5(v_run || x.entity || x.ref), 50), v_run, 'SILVER', x.entity, x.ref,
         x.version::text, 'financial_load_validation', '1', 'FINANCIAL_LOAD', x.problem,
         'ERROR', now(), 'OPEN'
  FROM (
    SELECT 'banking_account' AS entity, source_account_reference AS ref, source_record_version AS version,
           CASE WHEN customer_id IS NULL THEN 'NO_ACCEPTED_CUSTOMER_MATCH'
                WHEN currency_code <> 'AUD' THEN 'NON_AUD_CURRENCY'
                WHEN operation_type = 'D' THEN 'DELETE_NEEDS_REVIEW' END AS problem
    FROM tmp_account
    UNION ALL
    SELECT 'loan', source_loan_reference, source_record_version,
           CASE WHEN customer_id IS NULL THEN 'NO_ACCEPTED_CUSTOMER_MATCH'
                WHEN operation_type = 'D' THEN 'DELETE_NEEDS_REVIEW' END
    FROM tmp_loan
  ) x
  WHERE x.problem IS NOT NULL;

  -- Insert or update valid accounts.
  INSERT INTO silver.banking_account AS t (
    account_id, customer_id, source_system_id, source_account_reference, account_type,
    account_status, current_balance, opened_date, closed_date, source_last_updated_at,
    as_of_date, daily_income, daily_cost, credit_exposure)
  SELECT 'ACC-' || md5(source_system_id || '|' || source_account_reference), customer_id,
         source_system_id, source_account_reference, account_type, account_status,
         current_balance, opened_date, closed_date, source_last_updated_at, as_of_date,
         daily_income, daily_cost, credit_exposure
  FROM tmp_account
  WHERE customer_id IS NOT NULL AND currency_code = 'AUD' AND operation_type <> 'D'
  ON CONFLICT (account_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id, account_type = EXCLUDED.account_type,
    account_status = EXCLUDED.account_status, current_balance = EXCLUDED.current_balance,
    opened_date = EXCLUDED.opened_date, closed_date = EXCLUDED.closed_date,
    source_last_updated_at = EXCLUDED.source_last_updated_at, as_of_date = EXCLUDED.as_of_date,
    daily_income = EXCLUDED.daily_income, daily_cost = EXCLUDED.daily_cost,
    credit_exposure = EXCLUDED.credit_exposure
  WHERE (t.*) IS DISTINCT FROM (EXCLUDED.*);

  -- Insert or update valid loans (loans are treated as AUD).
  INSERT INTO silver.loan AS t (
    loan_id, customer_id, source_system_id, source_loan_reference, loan_type, loan_status,
    original_amount, outstanding_balance, interest_rate, start_date, maturity_date,
    source_last_updated_at, as_of_date, daily_income, daily_cost, credit_exposure)
  SELECT 'LOAN-' || md5(source_system_id || '|' || source_loan_reference), customer_id,
         source_system_id, source_loan_reference, loan_type, loan_status, original_amount,
         outstanding_balance, interest_rate, start_date, maturity_date,
         source_last_updated_at, as_of_date, daily_income, daily_cost, credit_exposure
  FROM tmp_loan
  WHERE customer_id IS NOT NULL AND operation_type <> 'D'
  ON CONFLICT (loan_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id, loan_type = EXCLUDED.loan_type,
    loan_status = EXCLUDED.loan_status, original_amount = EXCLUDED.original_amount,
    outstanding_balance = EXCLUDED.outstanding_balance, interest_rate = EXCLUDED.interest_rate,
    start_date = EXCLUDED.start_date, maturity_date = EXCLUDED.maturity_date,
    source_last_updated_at = EXCLUDED.source_last_updated_at, as_of_date = EXCLUDED.as_of_date,
    daily_income = EXCLUDED.daily_income, daily_cost = EXCLUDED.daily_cost,
    credit_exposure = EXCLUDED.credit_exposure
  WHERE (t.*) IS DISTINCT FROM (EXCLUDED.*);

  -- Insert new transactions for accounts already in Silver.
  INSERT INTO silver.account_transaction (
    transaction_id, account_id, source_system_id, source_transaction_reference,
    transaction_date, transaction_type, transaction_amount, transaction_status)
  SELECT 'TXN-' || md5(r.source_system_id || '|' || r.source_transaction_reference),
         a.account_id, r.source_system_id, r.source_transaction_reference,
         r.transaction_date, r.transaction_type, r.transaction_amount, r.transaction_status
  FROM bronze.raw_account_transaction r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  JOIN silver.banking_account a
    ON a.source_system_id = r.source_system_id
   AND a.source_account_reference = r.source_account_reference
  WHERE r.transaction_date < p_date + 1
  ON CONFLICT (transaction_id) DO NOTHING;

  -- Mark that the load for this date has run.
  INSERT INTO silver.data_lineage_record (
    lineage_id, transformation_run_id, source_layer, source_entity_name,
    source_record_reference, source_version_reference, source_record_snapshot,
    target_layer, target_entity_name, target_record_reference, target_version_reference,
    target_record_snapshot, transformation_name, transformation_version, transformation_timestamp)
  VALUES (v_run, v_run, 'BRONZE', 'financial_products', p_date::text, p_date::text,
          '{}', 'SILVER', 'financial_products', p_date::text, p_date::text,
          '{}', 'load_financials', '1', now())
  ON CONFLICT (lineage_id) DO UPDATE SET transformation_timestamp = EXCLUDED.transformation_timestamp;
END;
$$;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/01_load_silver_financials.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/02_load_dim_customer.sql

-- Step 2: Keep customer history in DIM_CUSTOMER (SCD Type 2).
-- Run: CALL gold.load_dim_customer();
BEGIN;

-- Generate customer_key for each new version.
CREATE SEQUENCE IF NOT EXISTS gold.dim_customer_key_seq AS bigint;

-- Allow only one current version per customer.
CREATE UNIQUE INDEX IF NOT EXISTS dim_customer_one_current
  ON gold.dim_customer (customer_id) WHERE current_flag;

-- Update the customer dimension from silver.customer_master.
CREATE OR REPLACE PROCEDURE gold.load_dim_customer()
LANGUAGE plpgsql AS $$
BEGIN
  -- Move the key sequence past any existing key.
  PERFORM setval('gold.dim_customer_key_seq', max(customer_key))
  FROM gold.dim_customer
  HAVING max(customer_key) >= (SELECT last_value FROM gold.dim_customer_key_seq);

  -- Stop if a change has no later update time.
  IF EXISTS (
    SELECT 1 FROM gold.dim_customer d
    JOIN silver.customer_master c ON c.customer_id = d.customer_id
    WHERE d.current_flag
      AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status)
      AND c.last_updated_at <= d.effective_from
  ) THEN
    RAISE EXCEPTION 'Customer name/status changed without a later last_updated_at';
  END IF;

  -- Close the current version when name or status changed.
  UPDATE gold.dim_customer d
  SET effective_to = c.last_updated_at, current_flag = false
  FROM silver.customer_master c
  WHERE c.customer_id = d.customer_id AND d.current_flag
    AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status);

  -- Open a new current version for new or changed customers.
  INSERT INTO gold.dim_customer (
    customer_key, customer_id, customer_full_name, customer_status,
    effective_from, effective_to, current_flag)
  -- A brand-new customer starts from its earliest matched source record, so past dates are covered.
  SELECT nextval('gold.dim_customer_key_seq'), c.customer_id, c.customer_full_name, c.customer_status,
         CASE WHEN EXISTS (SELECT 1 FROM gold.dim_customer d WHERE d.customer_id = c.customer_id)
              THEN c.last_updated_at
              ELSE least(c.last_updated_at, s.first_seen) END,
         NULL, true
  FROM silver.customer_master c
  LEFT JOIN (
    SELECT m.customer_id, min(r.source_last_updated_at) AS first_seen
    FROM silver.customer_source_match m
    JOIN silver.source_customer_record r ON r.source_customer_record_id = m.source_customer_record_id
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
    GROUP BY m.customer_id
  ) s ON s.customer_id = c.customer_id
  WHERE c.customer_status <> 'PENDING_SURVIVORSHIP'
    AND nullif(btrim(c.customer_full_name), '') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM gold.dim_customer d
                    WHERE d.customer_id = c.customer_id AND d.current_flag)
  ORDER BY c.customer_id;
END;
$$;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/02_load_dim_customer.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/03_customer_financials.sql

-- Step 3: Calculate each customer's financial totals for one date.
-- Run: SELECT * FROM gold.customer_financials(DATE '2026-09-15');
BEGIN;

-- Return one row of financial totals per customer.
CREATE OR REPLACE FUNCTION gold.customer_financials(p_date date)
RETURNS TABLE (
  customer_id varchar(50),
  total_account_balance numeric, total_outstanding_loans numeric,
  total_overdraft_balance numeric, total_debt numeric,
  banking_credit_exposure numeric, lending_credit_exposure numeric,
  total_credit_exposure numeric,
  total_income numeric, total_cost numeric, net_profit numeric,
  financial_data_status text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  -- Stop if step 1 has not run for this date.
  IF NOT EXISTS (SELECT 1 FROM silver.data_lineage_record WHERE lineage_id = 'FIN-' || p_date) THEN
    RAISE EXCEPTION 'Run CALL silver.load_financials(%) first', p_date;
  END IF;
  -- Stop if step 1 left open data issues.
  IF EXISTS (SELECT 1 FROM silver.data_quality_issue
             WHERE validation_run_id = 'FIN-' || p_date AND issue_status = 'OPEN') THEN
    RAISE EXCEPTION 'Financial load for % has open issues; see silver.data_quality_issue', p_date;
  END IF;

  -- Stop if any account or loan is from another date.
  IF EXISTS (SELECT 1 FROM silver.banking_account WHERE as_of_date <> p_date)
     OR EXISTS (SELECT 1 FROM silver.loan WHERE as_of_date <> p_date) THEN
    RAISE EXCEPTION 'Silver accounts/loans are not all dated %; run silver.load_financials for that date', p_date;
  END IF;

  RETURN QUERY
  -- List every account and loan as one row each (no join, so no double counting).
  WITH p AS (
    SELECT a.customer_id, a.current_balance AS balance, 0 AS outstanding,
           greatest(-a.current_balance, 0) AS overdraft,
           a.credit_exposure AS bank_exp, 0 AS lend_exp, a.daily_income AS income, a.daily_cost AS cost
    FROM silver.banking_account a
    UNION ALL
    SELECT l.customer_id, 0, l.outstanding_balance, 0,
           0, l.credit_exposure, l.daily_income, l.daily_cost
    FROM silver.loan l
  ), g AS (
    -- Total per customer; exposure, income and cost stay NULL if any value is missing.
    SELECT c.customer_id,
           COALESCE(sum(p.balance), 0) AS balance,
           COALESCE(sum(p.outstanding), 0) AS outstanding,
           COALESCE(sum(p.overdraft), 0) AS overdraft,
           CASE WHEN count(p.bank_exp) = count(p.customer_id) THEN COALESCE(sum(p.bank_exp), 0) END AS bank_exp,
           CASE WHEN count(p.lend_exp) = count(p.customer_id) THEN COALESCE(sum(p.lend_exp), 0) END AS lend_exp,
           CASE WHEN count(p.income) = count(p.customer_id) THEN COALESCE(sum(p.income), 0) END AS income,
           CASE WHEN count(p.cost) = count(p.customer_id) THEN COALESCE(sum(p.cost), 0) END AS cost
    FROM silver.customer_master c
    LEFT JOIN p ON p.customer_id = c.customer_id
    GROUP BY c.customer_id
  )
  -- Calculate debt, total exposure, net profit and data status.
  SELECT g.customer_id, g.balance, g.outstanding, g.overdraft, g.outstanding + g.overdraft,
         g.bank_exp, g.lend_exp, g.bank_exp + g.lend_exp,
         g.income, g.cost, g.income - g.cost,
         CASE WHEN g.bank_exp IS NULL OR g.lend_exp IS NULL OR g.income IS NULL OR g.cost IS NULL
              THEN 'PARTIAL' ELSE 'COMPLETE' END
  FROM g;
END;
$$;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/03_customer_financials.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/04_customer_risk_assessment.sql

-- Step 4: Assess each customer's risk from exposure and Member5's KYC/AML results.
-- Run: CALL silver.assess_customer_risk(DATE '2026-09-15', '<rules json>');

BEGIN;

-- Return each customer's KYC status and AML level on a date.
CREATE OR REPLACE FUNCTION gold.customer_compliance(p_date date)
RETURNS TABLE (customer_id varchar(50), kyc_status varchar(30), aml_risk_level varchar(30))
LANGUAGE sql STABLE AS $$
  SELECT c.customer_id,
         -- KYC: latest verification, EXPIRED if past expiry, else UNKNOWN.
         COALESCE((SELECT CASE WHEN k.expiry_date < p_date THEN 'EXPIRED' ELSE k.verification_status END
                   FROM silver.kyc_verification_record k
                   WHERE k.customer_id = c.customer_id AND k.verification_date < p_date + 1
                   ORDER BY k.verification_date DESC LIMIT 1), 'UNKNOWN'),
         -- AML: latest open case, else latest screening, else UNKNOWN.
         COALESCE((SELECT a.risk_level FROM silver.aml_case a
                   WHERE a.customer_id = c.customer_id AND a.opened_at < p_date + 1
                     AND (a.closed_at IS NULL OR a.closed_at >= p_date + 1)
                   ORDER BY a.opened_at DESC LIMIT 1),
                  (SELECT s.screening_result FROM silver.aml_screening_result s
                   WHERE s.customer_id = c.customer_id AND s.screening_date < p_date + 1
                   ORDER BY s.screening_date DESC LIMIT 1),
                  'UNKNOWN')
  FROM silver.customer_master c;
$$;

-- Match each customer to one risk rule and save the result.
CREATE OR REPLACE PROCEDURE silver.assess_customer_risk(p_date date, p_rules jsonb)
LANGUAGE plpgsql AS $$
BEGIN
  -- Stop if the rules JSON is missing name, version or rules.
  IF p_rules->>'rule_name' IS NULL OR p_rules->>'rule_version' IS NULL
     OR jsonb_typeof(p_rules->'rules') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Rules JSON needs rule_name, rule_version and a rules array';
  END IF;

  -- Stop if any rule is missing a required field.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rules->'rules') x
             WHERE NOT jsonb_strip_nulls(x) ?& ARRAY['kyc_status', 'aml_risk_level', 'exposure_min',
                                  'score', 'rating', 'kyc_risk_rating', 'aml_risk_rating', 'reason']) THEN
    RAISE EXCEPTION 'Each rule needs kyc_status, aml_risk_level, exposure_min, score, rating, kyc_risk_rating, aml_risk_rating and reason';
  END IF;

  -- Match customers to rules by KYC, AML and exposure range.
  DROP TABLE IF EXISTS tmp_risk;
  CREATE TEMP TABLE tmp_risk ON COMMIT DROP AS
  -- Turn the JSON rules into a table.
  WITH rules AS (
    SELECT x->>'kyc_status' AS kyc_status, x->>'aml_risk_level' AS aml_risk_level,
           (x->>'exposure_min')::numeric AS exposure_min,
           (x->>'exposure_max')::numeric AS exposure_max, x AS rule
    FROM jsonb_array_elements(p_rules->'rules') x
  )
  SELECT f.customer_id, f.total_credit_exposure, r.rule
  FROM gold.customer_financials(p_date) f
  JOIN gold.customer_compliance(p_date) c ON c.customer_id = f.customer_id
  LEFT JOIN rules r
    ON r.kyc_status = c.kyc_status AND r.aml_risk_level = c.aml_risk_level
   AND f.total_credit_exposure >= r.exposure_min
   AND (r.exposure_max IS NULL OR f.total_credit_exposure < r.exposure_max)
  WHERE f.total_credit_exposure IS NOT NULL;

  -- Stop unless each customer matched exactly one rule.
  IF EXISTS (SELECT 1 FROM tmp_risk GROUP BY customer_id HAVING count(rule) <> 1) THEN
    RAISE EXCEPTION 'Every assessable customer must match exactly one risk rule';
  END IF;

  -- Save a new assessment version; skip if nothing changed.
  INSERT INTO silver.customer_risk_assessment (
    risk_assessment_id, customer_id, assessment_date, assessment_version, risk_score,
    risk_rating, credit_exposure, aml_risk_rating, kyc_risk_rating, assessment_reason,
    assessment_rule, assessment_rule_version, valid_until, recorded_at)
  SELECT 'RA-' || md5(t.customer_id || '|' || p_date || '|' || (COALESCE(v.last_version, 0) + 1)),
         t.customer_id, p_date::timestamp, COALESCE(v.last_version, 0) + 1,
         (t.rule->>'score')::numeric(7,4), t.rule->>'rating', t.total_credit_exposure,
         t.rule->>'aml_risk_rating', t.rule->>'kyc_risk_rating', t.rule->>'reason',
         p_rules->>'rule_name', p_rules->>'rule_version', p_date + 1, now()
  FROM tmp_risk t
  LEFT JOIN (
    SELECT a.customer_id, max(a.assessment_version) AS last_version
    FROM silver.customer_risk_assessment a
    WHERE a.assessment_date = p_date::timestamp
    GROUP BY a.customer_id
  ) v ON v.customer_id = t.customer_id
  WHERE NOT EXISTS (
    SELECT 1 FROM silver.customer_risk_assessment a
    WHERE a.customer_id = t.customer_id AND a.assessment_date = p_date::timestamp
      AND a.assessment_version = v.last_version
      AND a.assessment_rule_version = p_rules->>'rule_version'
      AND a.risk_score = (t.rule->>'score')::numeric(7,4)
      AND a.risk_rating = t.rule->>'rating'
      AND a.credit_exposure = t.total_credit_exposure);
END;
$$;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/04_customer_risk_assessment.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/05_customer_snapshot.sql

-- Step 5: Publish the daily customer snapshot (FACT_CUSTOMER_SNAPSHOT).
-- Run: CALL gold.publish_snapshot(DATE '2026-09-15', '<rules json>');
-- Correct a published date: CALL gold.publish_snapshot(DATE '2026-09-15', '<rules json>', true);
BEGIN;

-- Build and save one snapshot row per customer for a date.
CREATE OR REPLACE PROCEDURE gold.publish_snapshot(
  p_date date, p_rules jsonb, p_allow_correction boolean DEFAULT false)
LANGUAGE plpgsql AS $$
BEGIN
  -- Run the risk assessment for this date.
  CALL silver.assess_customer_risk(p_date, p_rules);

  -- Stop if a customer with products has no valid dimension version.
  IF EXISTS (
    SELECT 1 FROM silver.customer_master c
    WHERE (EXISTS (SELECT 1 FROM silver.banking_account a WHERE a.customer_id = c.customer_id)
           OR EXISTS (SELECT 1 FROM silver.loan l WHERE l.customer_id = c.customer_id))
      AND NOT EXISTS (SELECT 1 FROM gold.dim_customer d
                      WHERE d.customer_id = c.customer_id AND d.effective_from < p_date + 1
                        AND (d.effective_to IS NULL OR d.effective_to >= p_date + 1))
  ) THEN
    RAISE EXCEPTION 'A customer with products has no dimension version on %; run gold.load_dim_customer()', p_date;
  END IF;

  -- Build the new snapshot rows in a temp table.
  DROP TABLE IF EXISTS tmp_snapshot;
  CREATE TEMP TABLE tmp_snapshot (LIKE gold.fact_customer_snapshot) ON COMMIT DROP;
  INSERT INTO tmp_snapshot
  SELECT 'SNAP-' || md5(f.customer_id || '|' || p_date) AS customer_snapshot_id,
         f.customer_id, d.customer_key, a.risk_assessment_id, p_date AS snapshot_date,
         f.total_account_balance, f.total_outstanding_loans, f.total_overdraft_balance,
         f.total_debt, f.banking_credit_exposure, f.lending_credit_exposure,
         f.total_credit_exposure, f.total_income, f.total_cost, f.net_profit,
         f.financial_data_status, a.risk_score, a.risk_rating,
         c.kyc_status, c.aml_risk_level, now()::timestamp AS calculated_at
  FROM gold.customer_financials(p_date) f
  JOIN gold.customer_compliance(p_date) c ON c.customer_id = f.customer_id
  JOIN gold.dim_customer d
    ON d.customer_id = f.customer_id
   AND d.effective_from < p_date + 1
   AND (d.effective_to IS NULL OR d.effective_to >= p_date + 1)
  -- Use the latest assessment of this date.
  LEFT JOIN (
    SELECT DISTINCT ON (x.customer_id) x.*
    FROM silver.customer_risk_assessment x
    WHERE x.assessment_date = p_date::timestamp
    ORDER BY x.customer_id, x.assessment_version DESC
  ) a ON a.customer_id = f.customer_id
  WHERE EXISTS (SELECT 1 FROM silver.banking_account b WHERE b.customer_id = f.customer_id)
     OR EXISTS (SELECT 1 FROM silver.loan l WHERE l.customer_id = f.customer_id);

  -- Stop if published rows would change, unless correction is allowed.
  IF NOT p_allow_correction AND EXISTS (
    SELECT 1 FROM gold.fact_customer_snapshot f
    LEFT JOIN tmp_snapshot t ON t.customer_snapshot_id = f.customer_snapshot_id
    WHERE f.snapshot_date = p_date
      AND (to_jsonb(f) - 'calculated_at') IS DISTINCT FROM (to_jsonb(t) - 'calculated_at')
  ) THEN
    RAISE EXCEPTION 'Snapshot for % changed; rerun with p_allow_correction => true to correct it', p_date;
  END IF;

  -- Remove rows for customers no longer in the snapshot.
  DELETE FROM gold.fact_customer_snapshot f
  WHERE f.snapshot_date = p_date
    AND NOT EXISTS (SELECT 1 FROM tmp_snapshot t WHERE t.customer_snapshot_id = f.customer_snapshot_id);

  -- Insert new rows or update changed rows.
  INSERT INTO gold.fact_customer_snapshot AS f
  SELECT * FROM tmp_snapshot
  ON CONFLICT (customer_snapshot_id) DO UPDATE SET
    customer_key = EXCLUDED.customer_key, risk_assessment_id = EXCLUDED.risk_assessment_id,
    total_account_balance = EXCLUDED.total_account_balance,
    total_outstanding_loans = EXCLUDED.total_outstanding_loans,
    total_overdraft_balance = EXCLUDED.total_overdraft_balance, total_debt = EXCLUDED.total_debt,
    banking_credit_exposure = EXCLUDED.banking_credit_exposure,
    lending_credit_exposure = EXCLUDED.lending_credit_exposure,
    total_credit_exposure = EXCLUDED.total_credit_exposure,
    total_income = EXCLUDED.total_income, total_cost = EXCLUDED.total_cost,
    net_profit = EXCLUDED.net_profit, financial_data_status = EXCLUDED.financial_data_status,
    risk_score = EXCLUDED.risk_score, risk_rating = EXCLUDED.risk_rating,
    kyc_status = EXCLUDED.kyc_status, aml_risk_level = EXCLUDED.aml_risk_level,
    calculated_at = EXCLUDED.calculated_at
  WHERE (to_jsonb(f) - 'calculated_at') IS DISTINCT FROM (to_jsonb(EXCLUDED) - 'calculated_at');
END;
$$;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/05_customer_snapshot.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/06_reporting_views.sql

-- Step 6: Reporting views on the daily snapshots.
-- Example: SELECT * FROM gold.v_portfolio_health WHERE snapshot_date = DATE '2026-09-15';
BEGIN;

-- Portfolio Health Dashboard: portfolio totals per date.
CREATE OR REPLACE VIEW gold.v_portfolio_health AS
SELECT snapshot_date,
       count(*) AS customer_count,
       count(*) FILTER (WHERE financial_data_status = 'PARTIAL') AS partial_customer_count,
       count(*) FILTER (WHERE risk_assessment_id IS NULL) AS unassessed_customer_count,
       sum(total_account_balance) AS total_account_balance,
       sum(total_outstanding_loans) AS total_outstanding_loans,
       sum(total_overdraft_balance) AS total_overdraft_balance,
       sum(total_debt) AS total_debt,
       -- Show exposure and profit totals only when all values are known.
       CASE WHEN count(total_credit_exposure) = count(*) THEN sum(total_credit_exposure) END AS total_credit_exposure,
       CASE WHEN count(net_profit) = count(*) THEN sum(net_profit) END AS total_net_profit
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date;

-- Portfolio Health Dashboard: customers and debt per risk rating.
CREATE OR REPLACE VIEW gold.v_portfolio_risk_distribution AS
SELECT snapshot_date,
       COALESCE(risk_rating, 'UNASSESSED') AS risk_rating,
       count(*) AS customer_count,
       sum(total_debt) AS total_debt
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date, COALESCE(risk_rating, 'UNASSESSED');

-- Customer Risk Profile Report: each customer's risk history with reasons.
CREATE OR REPLACE VIEW gold.v_customer_risk_profile AS
SELECT s.snapshot_date, s.customer_id, d.customer_full_name, d.customer_status,
       s.total_account_balance, s.total_outstanding_loans, s.total_overdraft_balance, s.total_debt,
       s.total_credit_exposure, s.net_profit, s.financial_data_status,
       s.kyc_status, s.aml_risk_level, s.risk_score, s.risk_rating,
       r.kyc_risk_rating, r.aml_risk_rating, r.assessment_reason,
       r.assessment_rule, r.assessment_rule_version
FROM gold.fact_customer_snapshot s
JOIN gold.dim_customer d ON d.customer_key = s.customer_key
LEFT JOIN silver.customer_risk_assessment r ON r.risk_assessment_id = s.risk_assessment_id;

COMMIT;

-- <<< END SOURCE FILE: sql/module4_dan/06_reporting_views.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/00_add_compliance_constraints.sql

-- PostgreSQL 15+
-- Member 5: CHECK constraints for the case and fact tables, with supporting indexes.
-- Constraints are added behind a guard so the module can be rerun; a violation raises rather than being skipped.

DO $compliance_rules$
DECLARE
  v_constraint record;
BEGIN
  FOR v_constraint IN
    SELECT *
    FROM (VALUES
      (
        'ck_kyc_verification_record_subject',
        'silver.kyc_verification_record',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL',
        'A KYC verification event requires a customer or a source customer record.'
      ),
      (
        'ck_kyc_verification_record_verified_expiry',
        'silver.kyc_verification_record',
        'verification_status <> ''VERIFIED'' OR expiry_date IS NULL OR expiry_date >= verification_date::date',
        'A successful KYC check cannot expire before it was performed.'
      ),
      (
        'ck_kyc_verification_record_reviewer',
        'silver.kyc_verification_record',
        'verification_status <> ''MISSING_DOCUMENT'' OR reviewed_by IS NULL',
        'A gap event records the check that failed; reviewed_by belongs to a completed review.'
      ),
      (
        'ck_special_verification_case_subject',
        'silver.special_verification_case',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL OR match_id IS NOT NULL OR kyc_verification_id IS NOT NULL',
        'A case requires at least one subject or trigger reference, excluding the assignee.'
      ),
      (
        'ck_special_verification_case_type',
        'silver.special_verification_case',
        'case_type IN (''KYC_GAP'', ''IDENTITY_MISMATCH'', ''STATUS_DISCREPANCY'')',
        'Reportable KYC findings use the case types required by the report.'
      ),
      (
        'ck_special_verification_case_status',
        'silver.special_verification_case',
        'case_status IN (''OPEN'', ''IN_REVIEW'', ''RESOLVED'', ''CLOSED'')',
        'Case status is limited to the prototype investigation lifecycle.'
      ),
      (
        'ck_special_verification_case_resolution',
        'silver.special_verification_case',
        '(case_status IN (''OPEN'', ''IN_REVIEW'') AND resolved_at IS NULL AND resolution_outcome IS NULL) OR (case_status IN (''RESOLVED'', ''CLOSED'') AND resolved_at IS NOT NULL)',
        'RESOLVED requires resolved_at; an active case must not carry a resolution.'
      ),
      (
        'ck_special_verification_case_dates',
        'silver.special_verification_case',
        'resolved_at IS NULL OR resolved_at >= opened_at',
        'A case cannot be resolved before it was opened.'
      ),
      (
        'ck_special_verification_case_severity',
        'silver.special_verification_case',
        'severity IN (''LOW'', ''MEDIUM'', ''HIGH'', ''CRITICAL'')',
        'Case severity uses the prototype severity scale.'
      ),
      (
        'ck_aml_screening_result_subject',
        'silver.aml_screening_result',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL',
        'A screening event requires a customer or a source customer record.'
      ),
      (
        'ck_aml_screening_result_score',
        'silver.aml_screening_result',
        'match_score IS NULL OR (match_score >= 0 AND match_score <= 1)',
        'A match score is a probability between 0 and 1.'
      ),
      (
        'ck_aml_screening_result_review_flag',
        'silver.aml_screening_result',
        'screening_result IN (''CLEAR'', ''FALSE_POSITIVE'') OR review_required_flag',
        'An alert or potential match cannot be published without review.'
      ),
      (
        'ck_aml_case_subject_or_trigger',
        'silver.aml_case',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL OR aml_screening_id IS NOT NULL OR length(btrim(trigger_reference)) > 0',
        'An AML investigation requires a customer, a source record, a screening reference or another documented trigger.'
      ),
      (
        'ck_aml_case_status',
        'silver.aml_case',
        'case_status IN (''OPEN'', ''IN_REVIEW'', ''CLOSED'')',
        'AML case status is limited to the prototype investigation lifecycle.'
      ),
      (
        'ck_aml_case_lifecycle',
        'silver.aml_case',
        '(case_status = ''CLOSED'' AND closed_at IS NOT NULL) OR (case_status <> ''CLOSED'' AND closed_at IS NULL)',
        'Closing dates must agree with the corresponding case status.'
      ),
      (
        'ck_aml_case_dates',
        'silver.aml_case',
        'closed_at IS NULL OR closed_at >= opened_at',
        'An AML case cannot be closed before it was opened.'
      ),
      (
        'ck_aml_case_risk_level',
        'silver.aml_case',
        'risk_level IN (''LOW'', ''MEDIUM'', ''HIGH'', ''CRITICAL'')',
        'Case risk level uses the prototype risk scale.'
      ),
      (
        'ck_fact_compliance_exception_single_case',
        'gold.fact_compliance_exception',
        '(verification_case_id IS NOT NULL AND aml_case_id IS NULL AND exception_source_type = ''VERIFICATION'') OR (verification_case_id IS NULL AND aml_case_id IS NOT NULL AND exception_source_type = ''AML'')',
        'Exactly one originating case is required and it must agree with exception_source_type.'
      ),
      (
        'ck_fact_compliance_exception_days_open',
        'gold.fact_compliance_exception',
        'days_open >= 0',
        'Days open is a non-negative calendar-day count.'
      ),
      (
        'ck_fact_compliance_exception_dates',
        'gold.fact_compliance_exception',
        'resolved_date IS NULL OR resolved_date >= opened_date',
        'An exception cannot be resolved before it was opened.'
      )
    ) AS rule (constraint_name, table_name, predicate, description)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = v_constraint.constraint_name
        AND conrelid = v_constraint.table_name::regclass
    ) THEN
      RAISE NOTICE 'Constraint % already present; validated only',
        v_constraint.constraint_name;
    ELSE
      EXECUTE format(
        'ALTER TABLE %s ADD CONSTRAINT %I CHECK (%s)',
        v_constraint.table_name,
        v_constraint.constraint_name,
        v_constraint.predicate
      );
      RAISE NOTICE 'Added %: %',
        v_constraint.constraint_name,
        v_constraint.description;
    END IF;
  END LOOP;
END
$compliance_rules$;

-- Supporting indexes for the validation and case-reuse lookups.
CREATE INDEX IF NOT EXISTS ix_kyc_verification_record_customer
  ON silver.kyc_verification_record (customer_id, verification_date DESC);

CREATE INDEX IF NOT EXISTS ix_kyc_verification_record_source_customer
  ON silver.kyc_verification_record (source_customer_record_id);

CREATE INDEX IF NOT EXISTS ix_aml_screening_result_customer
  ON silver.aml_screening_result (customer_id, screening_date DESC);

CREATE INDEX IF NOT EXISTS ix_aml_screening_result_source_customer
  ON silver.aml_screening_result (source_customer_record_id);

CREATE INDEX IF NOT EXISTS ix_special_verification_case_open
  ON silver.special_verification_case (customer_id, case_type)
  WHERE case_status IN ('OPEN', 'IN_REVIEW');

CREATE INDEX IF NOT EXISTS ix_aml_case_open
  ON silver.aml_case (customer_id, case_type)
  WHERE case_status IN ('OPEN', 'IN_REVIEW');

CREATE INDEX IF NOT EXISTS ix_data_quality_issue_case
  ON silver.data_quality_issue (verification_case_id)
  WHERE verification_case_id IS NOT NULL;

-- <<< END SOURCE FILE: sql/module5_guanbo/00_add_compliance_constraints.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/01_seed_kyc_aml_bronze.sql

-- PostgreSQL 15+
-- Member 5: the Bronze-layer input for the KYC/AML module.
--
-- Why the seed data is written out as INSERTs rather than read from the CSV files:
--   the synthetic CSVs live in the repository, but reading them would depend on the
--   server being able to see a local Windows path, so the rows are inlined here instead.

-- Batch control rows: defined once, used by both the source and the Silver registry.
CREATE OR REPLACE PROCEDURE silver.seed_kyc_aml_batches()
LANGUAGE plpgsql
AS $seed_batches$
DECLARE
  v_batches constant text[][] := ARRAY[
    ['B1-AMLKYC', 'INITIAL',       '2026-09-01 08:22:00', '2026-09-01 08:25:00', '27', '27', NULL,         '2026-09-01'],
    ['B2-AMLKYC', 'SIMULATED_CDC', '2026-09-15 08:24:00', '2026-09-15 08:25:00', '1',  '1',  '2026-09-01', '2026-09-15']
  ];
  v_batch text[];
BEGIN
  FOREACH v_batch SLICE 1 IN ARRAY v_batches
  LOOP
    -- Simulated source systems.
    INSERT INTO source_systems.ingestion_batch (
      batch_id, source_system_id, load_type, started_at, completed_at,
      load_status, records_received, records_processed, watermark_start, watermark_end
    )
    VALUES (
      v_batch[1], 'AMLKYC', v_batch[2], v_batch[3]::timestamp, v_batch[4]::timestamp,
      'SUCCEEDED', v_batch[5]::integer, v_batch[6]::integer, v_batch[7], v_batch[8]
    )
    ON CONFLICT (batch_id) DO NOTHING;

    -- Integration control layer. Existing batches are left alone so Member 1's recorded failure state is not overwritten.
    INSERT INTO silver.ingestion_batch (
      batch_id, source_system_id, load_type, started_at, completed_at,
      load_status, records_received, records_processed, watermark_start, watermark_end
    )
    VALUES (
      v_batch[1], 'AMLKYC', v_batch[2], v_batch[3]::timestamp, v_batch[4]::timestamp,
      'SUCCEEDED', v_batch[5]::integer, v_batch[6]::integer, v_batch[7], v_batch[8]
    )
    ON CONFLICT (batch_id) DO NOTHING;
  END LOOP;
END;
$seed_batches$;

-- Source system definitions. Silver's foreign keys require these to exist first.
INSERT INTO silver.source_system (
  source_system_id, system_name, system_type, system_description, system_owner, active_flag
)
VALUES ('AMLKYC', 'AML/KYC', 'COMPLIANCE', 'Synthetic verification and screening source', 'Prototype team', true)
ON CONFLICT (source_system_id) DO UPDATE SET
  system_name = EXCLUDED.system_name,
  system_type = EXCLUDED.system_type,
  system_description = EXCLUDED.system_description,
  system_owner = EXCLUDED.system_owner,
  active_flag = EXCLUDED.active_flag;

INSERT INTO source_systems.source_system (
  source_system_id, system_name, system_type, system_description, system_owner, active_flag
)
VALUES ('AMLKYC', 'AML/KYC', 'COMPLIANCE', 'Synthetic verification and screening source', 'Prototype team', true)
ON CONFLICT (source_system_id) DO NOTHING;

CALL silver.seed_kyc_aml_batches();

DROP PROCEDURE silver.seed_kyc_aml_batches();

-- Raw KYC verification rows: data/synthetic/raw_kyc_verification.csv (batch B1-AMLKYC, 9 rows).
DO $seed_kyc_verification$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze already holds the B1-AMLKYC KYC rows; seed data skipped';
    RETURN;
  END IF;

  INSERT INTO bronze.raw_kyc_verification (
    bronze_record_reference, source_system_id, batch_id, source_kyc_reference,
    source_customer_reference, verification_type, verification_status,
    verification_date, expiry_date, risk_level_at_verification,
    reviewer_reference, ingested_at
  )
  VALUES
    ('BR-KYC-001', 'AMLKYC', 'B1-AMLKYC', 'VFY-001', 'KYC-001', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-002', 'AMLKYC', 'B1-AMLKYC', 'VFY-003', 'KYC-003', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-003', 'AMLKYC', 'B1-AMLKYC', 'VFY-004', 'KYC-004', 'IDENTITY_DOCUMENT', 'MISSING_DOCUMENT', timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-004', 'AMLKYC', 'B1-AMLKYC', 'VFY-005', 'KYC-005', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'MEDIUM', NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-005', 'AMLKYC', 'B1-AMLKYC', 'VFY-006', 'KYC-006', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-006', 'AMLKYC', 'B1-AMLKYC', 'VFY-009', 'KYC-009', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-007', 'AMLKYC', 'B1-AMLKYC', 'VFY-010', 'KYC-010', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-008', 'AMLKYC', 'B1-AMLKYC', 'VFY-012', 'KYC-012', 'IDENTITY_DOCUMENT', 'EXPIRED',          timestamp '2026-09-01 07:00:00', date '2026-08-15', 'LOW',    NULL, timestamp '2026-09-01 08:22:00'),
    ('BR-KYC-009', 'AMLKYC', 'B1-AMLKYC', 'VFY-014', 'KYC-014', 'IDENTITY_DOCUMENT', 'VERIFIED',         timestamp '2026-09-01 07:00:00', date '2028-09-01', 'LOW',    NULL, timestamp '2026-09-01 08:22:00');

  RAISE NOTICE 'Inserted 9 Bronze KYC verification rows for B1-AMLKYC';
END
$seed_kyc_verification$;

-- Raw AML screening rows: data/synthetic/raw_aml_screening.csv (9 for B1, 1 for B2).
DO $seed_aml_screening$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze already holds the B1-AMLKYC AML rows; seed data skipped';
  ELSE
    INSERT INTO bronze.raw_aml_screening (
      bronze_record_reference, source_system_id, batch_id, source_screening_reference,
      source_customer_reference, screening_type, screening_date, screening_result,
      match_score, provider_reference, review_required_flag, ingested_at
    )
    VALUES
      ('BR-SCR-001', 'AMLKYC', 'B1-AMLKYC', 'SCR-001-1', 'KYC-001', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-001', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-002', 'AMLKYC', 'B1-AMLKYC', 'SCR-003-1', 'KYC-003', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-003', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-003', 'AMLKYC', 'B1-AMLKYC', 'SCR-004-1', 'KYC-004', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-004', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-004', 'AMLKYC', 'B1-AMLKYC', 'SCR-005-1', 'KYC-005', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-005', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-005', 'AMLKYC', 'B1-AMLKYC', 'SCR-006-1', 'KYC-006', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-006', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-006', 'AMLKYC', 'B1-AMLKYC', 'SCR-009-1', 'KYC-009', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-009', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-007', 'AMLKYC', 'B1-AMLKYC', 'SCR-010-1', 'KYC-010', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-010', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-008', 'AMLKYC', 'B1-AMLKYC', 'SCR-012-1', 'KYC-012', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-012', false, timestamp '2026-09-01 08:23:00'),
      ('BR-SCR-009', 'AMLKYC', 'B1-AMLKYC', 'SCR-014-1', 'KYC-014', 'SANCTIONS', timestamp '2026-09-01 07:20:00', 'CLEAR', 0.0200, 'SYN-014', false, timestamp '2026-09-01 08:23:00');

    RAISE NOTICE 'Inserted 9 Bronze AML screening rows for B1-AMLKYC';
  END IF;

  -- The B2 row is a suspected watchlist hit, and is the source of the reported AML exception.
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = 'B2-AMLKYC') THEN
    RAISE NOTICE 'Bronze already holds the B2-AMLKYC AML row; seed data skipped';
  ELSE
    INSERT INTO bronze.raw_aml_screening (
      bronze_record_reference, source_system_id, batch_id, source_screening_reference,
      source_customer_reference, screening_type, screening_date, screening_result,
      match_score, provider_reference, review_required_flag, ingested_at
    )
    VALUES
      ('BR-SCR-010', 'AMLKYC', 'B2-AMLKYC', 'SCR-005-2', 'KYC-005', 'WATCHLIST', timestamp '2026-09-15 07:25:00', 'POTENTIAL_MATCH', 0.9200, 'SYN-HIT-005', true, timestamp '2026-09-15 08:24:00');

    RAISE NOTICE 'Inserted 1 Bronze AML screening row for B2-AMLKYC: suspected watchlist hit';
  END IF;
END
$seed_aml_screening$;

-- ============================================================================
-- AML/KYC customer profile rows: data/synthetic/raw_aml_kyc_customer.csv (9 rows).
-- These attributes give the module's events a customer identity, so a report shows a real name rather than a placeholder.
-- The KYC-nnn references match the source customer references used by the events above.
-- ============================================================================
DO $seed_aml_kyc_customer$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze already holds the AML/KYC customer profiles; seed data skipped';
    RETURN;
  END IF;

  INSERT INTO bronze.raw_aml_kyc_customer (
    bronze_record_reference, source_system_id, batch_id, source_customer_reference,
    source_record_version, operation_type, source_full_name, source_date_of_birth,
    source_email_address, source_phone_number, source_address, record_status,
    source_last_updated_at, ingested_at
  )
  VALUES
    ('BR-AML-C-001', 'AMLKYC', 'B1-AMLKYC', 'KYC-001', 1, 'I', 'Alice Wong',    date '1985-03-12', 'alice.wong@example.test',    '0412001001', '18 Harbour Street, Sydney NSW 2000', 'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-002', 'AMLKYC', 'B1-AMLKYC', 'KYC-003', 1, 'I', 'Maya Patel',    date '1990-07-23', 'maya.patel@example.test',    '0412001003', '9 Ocean Avenue, Bondi NSW 2026',     'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-003', 'AMLKYC', 'B1-AMLKYC', 'KYC-004', 1, 'I', 'Noah Chen',     date '1979-11-05', 'noah.chen@example.test',     '0412001004', '5 Garden Road, Parramatta NSW 2150', 'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-004', 'AMLKYC', 'B1-AMLKYC', 'KYC-005', 1, 'I', 'Olivia Brooks', date '1992-06-17', 'olivia.brooks@example.test', '0412001005', '11 Lake Road, Chatswood NSW 2067',   'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-005', 'AMLKYC', 'B1-AMLKYC', 'KYC-006', 1, 'I', 'Ethan Nguyen',  date '1983-02-09', 'ethan.nguyen@example.test',  '0412001006', '27 Pine Street, Newtown NSW 2042',   'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-006', 'AMLKYC', 'B1-AMLKYC', 'KYC-009', 1, 'I', 'Zoe Kim',       date '1999-01-31', 'zoe.kim@example.test',       '0412001009', '8 Bridge Street, Sydney NSW 2000',   'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-007', 'AMLKYC', 'B1-AMLKYC', 'KYC-010', 1, 'I', 'Grace Wilson',  date '1981-12-04', 'grace.wilson@example.test',  '0412001010', '12 Park Avenue, Liverpool NSW 2170', 'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-008', 'AMLKYC', 'B1-AMLKYC', 'KYC-012', 1, 'I', 'Leo Martin',    date '1968-10-07', 'leo.martin@example.test',    '0412001012', '16 Bay Street, Rockdale NSW 2216',   'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00'),
    ('BR-AML-C-009', 'AMLKYC', 'B1-AMLKYC', 'KYC-014', 1, 'I', 'Lucas Park',    date '1991-04-19', 'lucas.park@example.test',    '0412001014', '7 North Street, Burwood NSW 2134',   'ACTIVE', timestamp '2026-09-01 07:40:00', timestamp '2026-09-01 08:14:00');

  RAISE NOTICE 'Inserted 9 Bronze AML/KYC customer profile rows';
END
$seed_aml_kyc_customer$;

-- <<< END SOURCE FILE: sql/module5_guanbo/01_seed_kyc_aml_bronze.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/02_load_kyc_aml_dimensions.sql

-- PostgreSQL 15+
-- Member 5: create the minimum customer identity that this module's events reference.
-- silver.customer_master and silver.source_customer_record belong to Member 2's identity
-- resolution. Only missing identities are added, so resolved results are never changed.

CREATE OR REPLACE PROCEDURE silver.load_kyc_aml_customer_identity()
LANGUAGE plpgsql
AS $load_identity$
DECLARE
  v_reference_count integer;
  v_created_customers integer;
  v_created_source_records integer;
  v_linked_records integer;
BEGIN
  DROP TABLE IF EXISTS tmp_kyc_aml_reference;
  CREATE TEMP TABLE tmp_kyc_aml_reference (
    source_customer_reference varchar(100) PRIMARY KEY,
    earliest_event_at timestamp NOT NULL
  )
  ON COMMIT DROP;

  INSERT INTO tmp_kyc_aml_reference (source_customer_reference, earliest_event_at)
  SELECT
    source_reference.source_customer_reference,
    min(source_reference.first_seen_at)
  FROM (
    SELECT
      btrim(raw.source_customer_reference) AS source_customer_reference,
      min(raw.verification_date) AS first_seen_at
    FROM bronze.raw_kyc_verification raw
    WHERE COALESCE(btrim(raw.source_customer_reference), '') <> ''
    GROUP BY btrim(raw.source_customer_reference)
    UNION ALL
    SELECT
      btrim(raw.source_customer_reference) AS source_customer_reference,
      min(raw.screening_date) AS first_seen_at
    FROM bronze.raw_aml_screening raw
    WHERE COALESCE(btrim(raw.source_customer_reference), '') <> ''
    GROUP BY btrim(raw.source_customer_reference)
  ) source_reference
  GROUP BY source_reference.source_customer_reference;

  SELECT count(*)::integer
  INTO v_reference_count
  FROM tmp_kyc_aml_reference;

  -- One retained Silver record per source customer identity.
  DROP TABLE IF EXISTS tmp_kyc_aml_source_record;
  CREATE TEMP TABLE tmp_kyc_aml_source_record
  ON COMMIT DROP
  AS
  SELECT
    source_reference.source_customer_reference,
    'SCR-' || upper(substr(md5('AMLKYC:' || source_reference.source_customer_reference), 1, 16))
      AS source_customer_record_id
  FROM tmp_kyc_aml_reference source_reference;

  INSERT INTO silver.source_customer_record (
    source_customer_record_id,
    source_system_id,
    batch_id,
    source_customer_reference,
    source_record_version,
    bronze_record_reference,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,
    source_last_updated_at,
    valid_from,
    valid_to,
    is_current_version,
    record_hash
  )
  SELECT
    staged.source_customer_record_id,
    'AMLKYC',
    COALESCE(raw.batch_id, 'B1-AMLKYC'),
    staged.source_customer_reference,
    COALESCE(raw.source_record_version, 1),
    COALESCE(raw.bronze_record_reference, 'BR-AMLKYC-CUSTOMER-' || staged.source_customer_reference),
    raw.source_full_name,
    raw.source_date_of_birth,
    raw.source_email_address,
    raw.source_phone_number,
    raw.source_address,
    raw.source_last_updated_at,
    COALESCE(source_reference.earliest_event_at, timestamp '2026-09-01 07:00:00'),
    NULL,
    true,
    md5(
      concat_ws(
        '|',
        'AMLKYC',
        staged.source_customer_reference,
        COALESCE(raw.source_full_name, ''),
        COALESCE(raw.source_email_address, ''),
        COALESCE(raw.source_phone_number, '')
      )
    )
  FROM tmp_kyc_aml_source_record staged
  JOIN tmp_kyc_aml_reference source_reference
    ON source_reference.source_customer_reference = staged.source_customer_reference
  LEFT JOIN LATERAL (
    SELECT
      retained.batch_id,
      retained.source_record_version,
      retained.bronze_record_reference,
      retained.source_full_name,
      retained.source_date_of_birth,
      retained.source_email_address,
      retained.source_phone_number,
      retained.source_address,
      retained.source_last_updated_at
    FROM bronze.raw_aml_kyc_customer retained
    WHERE retained.source_customer_reference = staged.source_customer_reference
    ORDER BY
      retained.source_record_version DESC,
      retained.source_last_updated_at DESC NULLS LAST,
      retained.bronze_record_reference DESC
    LIMIT 1
  ) raw ON true
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.source_customer_record existing
    WHERE existing.source_system_id = 'AMLKYC'
      AND existing.source_customer_reference = staged.source_customer_reference
  );

  GET DIAGNOSTICS v_created_source_records = ROW_COUNT;

  -- A golden customer for any source record that has no identity mapping yet.
  DROP TABLE IF EXISTS tmp_kyc_aml_customer;
  CREATE TEMP TABLE tmp_kyc_aml_customer
  ON COMMIT DROP
  AS
  SELECT DISTINCT
    source_record.source_customer_reference,
    source_record.source_customer_record_id,
    'CUST-' || upper(substr(md5('AMLKYC:' || source_record.source_customer_reference), 1, 16))
      AS customer_id
  FROM silver.source_customer_record source_record
  WHERE source_record.source_system_id = 'AMLKYC'
    AND NOT EXISTS (
      SELECT 1
      FROM silver.customer_source_match existing_match
      WHERE existing_match.source_customer_record_id = source_record.source_customer_record_id
        AND existing_match.match_status = 'ACCEPTED'
        AND existing_match.is_current_match
    );

  INSERT INTO silver.customer_master (
    customer_id,
    customer_full_name,
    date_of_birth,
    email_address,
    phone_number,
    residential_address,
    suburb_city,
    state_region,
    postcode,
    country_code,
    customer_status,
    customer_since_date,
    created_at,
    last_updated_at
  )
  SELECT
    staged.customer_id,
    COALESCE(source_record.source_full_name, 'Unresolved customer ' || staged.source_customer_reference),
    source_record.source_date_of_birth,
    source_record.source_email_address,
    source_record.source_phone_number,
    source_record.source_address,
    NULL,
    NULL,
    NULL,
    NULL,
    'ACTIVE',
    source_record.valid_from::date,
    source_record.valid_from,
    COALESCE(source_record.source_last_updated_at, source_record.valid_from)
  FROM tmp_kyc_aml_customer staged
  JOIN silver.source_customer_record source_record
    ON source_record.source_customer_record_id = staged.source_customer_record_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.customer_master existing_customer
    WHERE existing_customer.customer_id = staged.customer_id
  );

  GET DIAGNOSTICS v_created_customers = ROW_COUNT;

  -- The match between the source record and that golden customer, with status ACCEPTED
  -- because both sides were created here. Cross-source matches remain Member 2's decision.
  INSERT INTO silver.customer_source_match (
    match_id,
    source_customer_record_id,
    customer_id,
    reviewed_by_user_id,
    match_status,
    match_confidence_score,
    match_rule,
    manual_review_flag,
    effective_from,
    effective_to,
    is_current_match,
    matched_at
  )
  SELECT
    'MATCH-' || upper(substr(md5(staged.source_customer_record_id), 1, 16)),
    staged.source_customer_record_id,
    staged.customer_id,
    NULL,
    'ACCEPTED',
    0.5000,
    'AMLKYC_SINGLE_SOURCE_IDENTITY',
    false,
    source_record.valid_from,
    NULL,
    true,
    source_record.valid_from
  FROM tmp_kyc_aml_customer staged
  JOIN silver.source_customer_record source_record
    ON source_record.source_customer_record_id = staged.source_customer_record_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.customer_source_match existing_match
    WHERE existing_match.source_customer_record_id = staged.source_customer_record_id
      AND existing_match.is_current_match
  );

  GET DIAGNOSTICS v_linked_records = ROW_COUNT;

  RAISE NOTICE
    'KYC/AML identity load: % source references, % new source records, % new customers, % new match decisions',
    v_reference_count,
    v_created_source_records,
    v_created_customers,
    v_linked_records;
END;
$load_identity$;

COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  'Creates the minimal customer identity required by this module''s KYC and AML events without altering any identity already resolved by Member 2.';

-- <<< END SOURCE FILE: sql/module5_guanbo/02_load_kyc_aml_dimensions.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/03_create_kyc_aml_load_procedures.sql

-- PostgreSQL 15+
-- Member 5: validate the Bronze KYC verification and AML screening rows and publish them to Silver.
--
-- Publication is driven by the presence of Bronze rows, not by the batch status:
--   B2-AMLKYC has a source row whose CDC operation_type is blank, so Member 1 marks that
--   batch FAILED on purpose, yet its retained rows are still reportable.

-- Section 1: steps shared by both publishers

-- Stage one batch's Bronze rows into a temp table and attach the identity lookup result.
--
-- The lookup answers two questions:
--   source_customer_record_id: which Silver record this source customer reference maps to
--   customer_id: which golden customer it merged into, when the merge succeeded
-- Both are NULL when nothing is found. The event is still published, and the rules then report the unresolved identity.
CREATE OR REPLACE PROCEDURE silver.stage_bronze_batch(
  p_entity varchar,
  p_batch_id varchar
)
LANGUAGE plpgsql
AS $stage_batch$
BEGIN
  IF p_entity = 'KYC' THEN
    DROP TABLE IF EXISTS tmp_staged;
    CREATE TEMP TABLE tmp_staged ON COMMIT DROP AS
    SELECT
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_kyc_reference) AS event_reference,
      btrim(raw.source_customer_reference) AS customer_reference,
      raw.verification_type AS event_type,
      raw.verification_status AS event_status,
      raw.verification_date AS event_time,
      raw.expiry_date,
      raw.risk_level_at_verification,
      raw.reviewer_reference,
      NULL::numeric AS match_score,
      NULL::varchar AS provider_reference,
      NULL::boolean AS review_required_flag,
      (
        SELECT min(source_record.source_customer_record_id)
        FROM silver.source_customer_record source_record
        WHERE source_record.source_system_id = raw.source_system_id
          AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
          AND source_record.is_current_version
      ) AS source_customer_record_id,
      (
        SELECT min(current_match.customer_id)
        FROM silver.source_customer_record source_record
        JOIN silver.customer_source_match current_match
          ON current_match.source_customer_record_id = source_record.source_customer_record_id
         AND current_match.is_current_match
         AND current_match.match_status = 'ACCEPTED'
        WHERE source_record.source_system_id = raw.source_system_id
          AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
      ) AS customer_id,
      (
        SELECT min(btrim(reviewer.user_id))
        FROM silver.user_account reviewer
        WHERE reviewer.username = btrim(COALESCE(raw.reviewer_reference, ''))
      ) AS reviewed_by
    FROM bronze.raw_kyc_verification raw
    WHERE raw.batch_id = p_batch_id;
  ELSIF p_entity = 'AML' THEN
    DROP TABLE IF EXISTS tmp_staged;
    CREATE TEMP TABLE tmp_staged ON COMMIT DROP AS
    SELECT
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_screening_reference) AS event_reference,
      btrim(raw.source_customer_reference) AS customer_reference,
      raw.screening_type AS event_type,
      raw.screening_result AS event_status,
      raw.screening_date AS event_time,
      NULL::date AS expiry_date,
      NULL::varchar AS risk_level_at_verification,
      NULL::varchar AS reviewer_reference,
      raw.match_score,
      raw.provider_reference,
      COALESCE(raw.review_required_flag, false) AS review_required_flag,
      (
        SELECT min(source_record.source_customer_record_id)
        FROM silver.source_customer_record source_record
        WHERE source_record.source_system_id = raw.source_system_id
          AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
          AND source_record.is_current_version
      ) AS source_customer_record_id,
      (
        SELECT min(current_match.customer_id)
        FROM silver.source_customer_record source_record
        JOIN silver.customer_source_match current_match
          ON current_match.source_customer_record_id = source_record.source_customer_record_id
         AND current_match.is_current_match
         AND current_match.match_status = 'ACCEPTED'
        WHERE source_record.source_system_id = raw.source_system_id
          AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
      ) AS customer_id,
      NULL::varchar AS reviewed_by
    FROM bronze.raw_aml_screening raw
    WHERE raw.batch_id = p_batch_id;
  ELSE
    RAISE EXCEPTION 'Unsupported entity %; expected KYC or AML', p_entity;
  END IF;
END;
$stage_batch$;

-- Record published events in the lineage table, linking the Bronze row to the Silver event.
-- Republishing the same row adds no duplicate lineage, because lineage_id is derived.
CREATE OR REPLACE PROCEDURE silver.record_event_lineage(
  p_entity varchar,
  p_batch_id varchar
)
LANGUAGE plpgsql
AS $record_lineage$
BEGIN
  INSERT INTO silver.data_lineage_record (
    lineage_id, batch_id, source_system_id, transformation_run_id,
    source_layer, source_entity_name, source_record_reference,
    source_version_reference, source_attribute_name, source_record_snapshot,
    target_layer, target_entity_name, target_record_reference,
    target_version_reference, target_attribute_name, target_record_snapshot,
    transformation_name, transformation_version, transformation_timestamp
  )
  SELECT
    'LIN-' || p_entity || '-' || upper(substr(md5(staged.bronze_record_reference), 1, 20)),
    staged.batch_id,
    staged.source_system_id,
    'KYC-AML-M5-' || staged.batch_id,
    'BRONZE',
    CASE p_entity WHEN 'KYC' THEN 'RAW_KYC_VERIFICATION' ELSE 'RAW_AML_SCREENING' END,
    staged.bronze_record_reference,
    staged.batch_id,
    NULL,
    concat_ws(
      '|',
      'event_reference=' || staged.event_reference,
      'event_type=' || staged.event_type,
      'event_status=' || staged.event_status,
      'event_time=' || staged.event_time::text
    ),
    'SILVER',
    CASE p_entity WHEN 'KYC' THEN 'KYC_VERIFICATION_RECORD' ELSE 'AML_SCREENING_RESULT' END,
    published.target_record_reference,
    staged.batch_id,
    NULL,
    concat_ws(
      '|',
      'customer_id=' || COALESCE(staged.customer_id, 'NULL'),
      'source_customer_record_id=' || COALESCE(staged.source_customer_record_id, 'NULL'),
      'event_status=' || staged.event_status
    ),
    CASE p_entity
      WHEN 'KYC' THEN 'PUBLISH_KYC_VERIFICATION_EVENT'
      ELSE 'PUBLISH_AML_SCREENING_EVENT'
    END,
    '1.0',
    COALESCE(staged.event_time, clock_timestamp())
  FROM tmp_staged staged
  JOIN (
    SELECT
      verification.source_system_id,
      verification.source_kyc_reference AS event_reference,
      verification.kyc_verification_id AS target_record_reference
    FROM silver.kyc_verification_record verification
    WHERE p_entity = 'KYC'
    UNION ALL
    SELECT
      screening.source_system_id,
      screening.source_screening_reference,
      screening.aml_screening_id
    FROM silver.aml_screening_result screening
    WHERE p_entity = 'AML'
  ) published
    ON published.source_system_id = staged.source_system_id
   AND published.event_reference = staged.event_reference
  ON CONFLICT (lineage_id) DO NOTHING;
END;
$record_lineage$;

-- Section 2: event publication, one procedure per event type with columns listed explicitly

-- Publish KYC verification events: stage and resolve identity, detect issues, publish the survivors.
CREATE OR REPLACE PROCEDURE silver.publish_kyc_verification_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $publish_kyc$
DECLARE
  v_staged_count integer;
  v_blocking_count integer;
  v_published_count integer := 0;
BEGIN
  CALL silver.stage_bronze_batch('KYC', p_batch_id);

  SELECT count(*)::integer INTO v_staged_count FROM tmp_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'Batch % has no KYC verification rows in Bronze; nothing to publish', p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_findings;
  CREATE TEMP TABLE tmp_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_blocking_count
  FROM tmp_findings WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.kyc_verification_record (
    kyc_verification_id, customer_id, source_customer_record_id, source_system_id,
    reviewed_by, source_kyc_reference, verification_type, verification_status,
    verification_date, expiry_date, risk_level_at_verification
  )
  SELECT
    silver.kyc_verification_id(staged.source_system_id, staged.event_reference),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.reviewed_by,
    staged.event_reference,
    staged.event_type,
    staged.event_status,
    staged.event_time,
    staged.expiry_date,
    staged.risk_level_at_verification
  FROM tmp_staged staged
  -- Rows with a blocking finding are not published.
  WHERE staged.bronze_record_reference NOT IN (
    SELECT finding.source_record_reference
    FROM tmp_findings finding
    WHERE finding.issue_severity = 'BLOCKING'
  )
  ON CONFLICT (source_system_id, source_kyc_reference) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    source_customer_record_id = EXCLUDED.source_customer_record_id,
    reviewed_by = EXCLUDED.reviewed_by,
    verification_type = EXCLUDED.verification_type,
    verification_status = EXCLUDED.verification_status,
    verification_date = EXCLUDED.verification_date,
    expiry_date = EXCLUDED.expiry_date,
    risk_level_at_verification = EXCLUDED.risk_level_at_verification;

  GET DIAGNOSTICS v_published_count = ROW_COUNT;

  CALL silver.record_event_lineage('KYC', p_batch_id);

  RAISE NOTICE 'Batch %: % KYC rows staged, % published, % blocked',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_kyc$;

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'Validate one batch of Bronze KYC verification rows and publish them to Silver, withholding rows that carry a blocking finding.';

-- Publish AML screening events: the same steps as the KYC publisher, against different tables.
CREATE OR REPLACE PROCEDURE silver.publish_aml_screening_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $publish_aml$
DECLARE
  v_staged_count integer;
  v_blocking_count integer;
  v_published_count integer := 0;
BEGIN
  CALL silver.stage_bronze_batch('AML', p_batch_id);

  SELECT count(*)::integer INTO v_staged_count FROM tmp_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'Batch % has no AML screening rows in Bronze; nothing to publish', p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_findings;
  CREATE TEMP TABLE tmp_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_blocking_count
  FROM tmp_findings WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.aml_screening_result (
    aml_screening_id, customer_id, source_customer_record_id, source_system_id,
    source_screening_reference, screening_type, screening_date, screening_result,
    match_score, provider_reference, review_required_flag
  )
  SELECT
    silver.aml_screening_id(staged.source_system_id, staged.event_reference),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.event_reference,
    staged.event_type,
    staged.event_time,
    staged.event_status,
    staged.match_score,
    staged.provider_reference,
    staged.review_required_flag
  FROM tmp_staged staged
  WHERE staged.bronze_record_reference NOT IN (
    SELECT finding.source_record_reference
    FROM tmp_findings finding
    WHERE finding.issue_severity = 'BLOCKING'
  )
  ON CONFLICT (source_system_id, source_screening_reference) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    source_customer_record_id = EXCLUDED.source_customer_record_id,
    screening_type = EXCLUDED.screening_type,
    screening_date = EXCLUDED.screening_date,
    screening_result = EXCLUDED.screening_result,
    match_score = EXCLUDED.match_score,
    provider_reference = EXCLUDED.provider_reference,
    review_required_flag = EXCLUDED.review_required_flag;

  GET DIAGNOSTICS v_published_count = ROW_COUNT;

  CALL silver.record_event_lineage('AML', p_batch_id);

  RAISE NOTICE 'Batch %: % AML rows staged, % published, % blocked',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_aml$;

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'Validate one batch of Bronze AML screening rows and publish them to Silver, withholding rows that carry a blocking finding.';

-- Section 3: the per-batch entry point

-- Run one batch end to end: resolve identity, publish both event types, then run the rules.
--
-- Findings are staged in a temp table that both the counting and the registration step reuse.
CREATE OR REPLACE PROCEDURE silver.process_kyc_aml_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $process_batch$
DECLARE
  v_source_system_id varchar(50);
  v_kyc_count integer;
  v_aml_count integer;
BEGIN
  IF p_reference_date IS NULL THEN
    RAISE EXCEPTION 'A reporting date is required to decide whether a KYC verification has expired';
  END IF;

  SELECT min(source_system_id)
  INTO v_source_system_id
  FROM (
    SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_sources;

  IF v_source_system_id IS NULL THEN
    RAISE EXCEPTION 'Batch % has neither KYC nor AML rows in Bronze', p_batch_id;
  END IF;

  -- Identity resolution scans every customer reference, so it runs once per session.
  CREATE TEMP TABLE IF NOT EXISTS tmp_identity_loaded (
    loaded_at timestamp NOT NULL
  ) ON COMMIT PRESERVE ROWS;

  IF NOT EXISTS (SELECT 1 FROM tmp_identity_loaded) THEN
    CALL silver.load_kyc_aml_customer_identity();
    INSERT INTO tmp_identity_loaded (loaded_at) VALUES (clock_timestamp());
  END IF;

  CALL silver.publish_kyc_verification_batch(p_batch_id, p_reference_date);
  CALL silver.publish_aml_screening_batch(p_batch_id, p_reference_date);

  -- Stage the rule findings so counting and registration share one evaluation.
  DROP TABLE IF EXISTS tmp_kyc_findings;
  CREATE TEMP TABLE tmp_kyc_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  DROP TABLE IF EXISTS tmp_aml_findings;
  CREATE TEMP TABLE tmp_aml_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_kyc_count FROM tmp_kyc_findings;
  SELECT count(*)::integer INTO v_aml_count FROM tmp_aml_findings;

  -- Register as data quality issues. Cases are opened by 05_create_case_processing.sql.
  PERFORM silver.register_compliance_finding(
    p_batch_id, v_source_system_id, 'KYC_VERIFICATION_RECORD',
    issue.source_record_reference, issue.source_batch_reference, issue.issue_attribute_name,
    issue.rule_name, issue.issue_type, issue.issue_description,
    issue.issue_severity, issue.rule_case_type
  )
  FROM tmp_kyc_findings issue;

  PERFORM silver.register_compliance_finding(
    p_batch_id, v_source_system_id, 'AML_SCREENING_RESULT',
    issue.source_record_reference, issue.source_batch_reference, issue.issue_attribute_name,
    issue.rule_name, issue.issue_type, issue.issue_description,
    issue.issue_severity, issue.rule_case_type
  )
  FROM tmp_aml_findings issue;

  RAISE NOTICE 'Batch % complete as of %: % KYC findings, % AML findings',
    p_batch_id, p_reference_date, v_kyc_count, v_aml_count;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Member 5 batch entry point: resolve customer identity, publish KYC and AML events to Silver, run the rules and register the findings.';

-- <<< END SOURCE FILE: sql/module5_guanbo/03_create_kyc_aml_load_procedures.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/04_create_kyc_aml_validation.sql

-- PostgreSQL 15+
-- Member 5: the KYC/AML validation rules, and registration of findings as data quality issues.
--
-- Layout: identifiers, identity resolution, 8 KYC rules, 10 AML rules, rule-to-case mapping, registration.
-- Design: each record keeps only its most severe finding, ordered by one shared ranking; a rule never
--       opens a case itself, and a NULL batch means every batch at its latest Bronze version.

-- The key is derived from the source system and reference, which gives two properties:
--   1. reprocessing the same data yields the same key, so inserts stay idempotent;
--   2. a published event can be located from its business reference without a lookup.
CREATE OR REPLACE FUNCTION silver.kyc_verification_id(
  p_source_system_id varchar,
  p_source_kyc_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $kyc_id$
  SELECT 'KYC-' || upper(substr(md5(p_source_system_id || ':' || p_source_kyc_reference), 1, 16));
$kyc_id$;

CREATE OR REPLACE FUNCTION silver.aml_screening_id(
  p_source_system_id varchar,
  p_source_screening_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $aml_id$
  SELECT 'AML-' || upper(substr(md5(p_source_system_id || ':' || p_source_screening_reference), 1, 16));
$aml_id$;

COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  'Stable verification event key derived from the source system and source KYC reference, so reprocessing adds no duplicate rows.';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  'Stable screening event key derived from the source system and source screening reference, as for the KYC version.';

-- Section 2: identity resolution, shared by both detection functions

-- An event has to answer who it is about. This function returns two identifiers:
--   source_customer_record_id: the Silver record for that source customer reference
--   customer_id: the golden customer it merged into, when the merge succeeded
-- Either is NULL when nothing is found, which is how a caller detects an unresolved identity.
CREATE OR REPLACE FUNCTION silver.resolve_event_identity(
  p_entity varchar,
  p_source_system_id varchar,
  p_source_reference varchar,
  p_batch_id varchar
)
RETURNS TABLE (
  source_customer_record_id varchar,
  customer_id varchar
)
LANGUAGE plpgsql
STABLE
AS $resolve_identity$
DECLARE
  v_customer_reference varchar(100);
BEGIN
  -- Read the source customer reference this event points at.
  IF p_entity = 'KYC' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_kyc_verification raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_kyc_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSIF p_entity = 'AML' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_aml_screening raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_screening_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSE
    RAISE EXCEPTION 'Unsupported entity %: expected KYC or AML', p_entity;
  END IF;

  SELECT min(source_record.source_customer_record_id)
  INTO source_customer_record_id
  FROM silver.source_customer_record source_record
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference
    AND source_record.is_current_version;

  -- Only a current ACCEPTED match counts as a confirmed identity.
  SELECT min(current_match.customer_id)
  INTO customer_id
  FROM silver.source_customer_record source_record
  JOIN silver.customer_source_match current_match
    ON current_match.source_customer_record_id = source_record.source_customer_record_id
   AND current_match.is_current_match
   AND current_match.match_status = 'ACCEPTED'
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference;

  RETURN NEXT;
END;
$resolve_identity$;

COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  'Resolve the source customer record and golden customer for one event. NULL means the identity is not merged yet.';

-- Section 3: the eight KYC verification rules

DROP FUNCTION IF EXISTS silver.detect_kyc_verification_issues(varchar, date);

CREATE OR REPLACE FUNCTION silver.detect_kyc_verification_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_kyc$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  -- One latest Bronze version per reference; a NULL batch means the latest across all batches.
  staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_kyc_reference))
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_kyc_reference) AS source_kyc_reference,
      btrim(raw.source_customer_reference) AS source_customer_reference,
      raw.verification_type,
      raw.verification_status,
      raw.verification_date,
      raw.expiry_date
    FROM bronze.raw_kyc_verification raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_kyc_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  -- Attach identity, and work out whether the type and status are recognised values.
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      reference_date.as_of_date,
      staged.verification_type IN (
        'IDENTITY_DOCUMENT', 'ADDRESS_VERIFICATION', 'SOURCE_OF_FUNDS',
        'ENHANCED_DUE_DILIGENCE', 'PERIODIC_REVIEW'
      ) AS type_is_known,
      staged.verification_status IN (
        'VERIFIED', 'PENDING', 'MISSING_DOCUMENT', 'FAILED', 'EXPIRED'
      ) AS status_is_known
    FROM staged
    CROSS JOIN reference_date
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'KYC', staged.source_system_id, staged.source_kyc_reference, p_batch_id
    ) identity
  ),
  -- Evaluate the eight rule conditions here; the blocks below project them into findings.
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- Expired. A verification dated after the reference date is not treated as expired.
      (
        evaluated.expiry_date IS NOT NULL
        AND evaluated.verification_date::date < evaluated.as_of_date
        AND evaluated.expiry_date < evaluated.as_of_date
        AND evaluated.verification_status NOT IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED')
      ) AS is_expired,
      -- Marked verified, but the recorded expiry no longer supports that claim.
      (
        evaluated.verification_status = 'VERIFIED'
        AND (
          evaluated.expiry_date IS NULL
          OR evaluated.expiry_date < evaluated.verification_date::date
          OR evaluated.expiry_date < evaluated.as_of_date
        )
      ) AS is_discrepancy,
      -- Verification did not complete, which is an evidence gap.
      evaluated.verification_status IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED') AS is_gap
    FROM evaluated
  ),
  -- Each rule block carries only what is specific to that rule: e.* expands the shared
  -- evaluated_rules columns, then the rule name, issue type, severity and dedup priority.
  -- The eight rules' hits, projected into one finding list.
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'KYC_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'KYC_SUBJECT_MISSING' AS issue_type,
      'This verification event has neither a golden customer nor a source customer record, so it carries no subject reference.' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'KYC_IDENTITY_LINK_MISMATCH', 'KYC_IDENTITY_MISMATCH',
      'The golden customer and the source customer record on this event are not the same confirmed identity.',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'verification_type', 'KYC_VERIFICATION_TYPE_INVALID', 'KYC_VERIFICATION_TYPE_INVALID',
      concat('Verification type ', COALESCE(e.verification_type, 'NULL'), ' is not a recognised KYC verification type.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_INVALID', 'KYC_VERIFICATION_STATUS_INVALID',
      concat('Verification status ', COALESCE(e.verification_status, 'NULL'), ' is not a recognised KYC verification status.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.status_is_known

    UNION ALL
    SELECT
      e.*,
      'expiry_date', 'KYC_VERIFICATION_EXPIRED', 'KYC_VERIFICATION_EXPIRED',
      concat(
        'Expired by the reporting date. Status ', e.verification_status,
        ', expiry ', COALESCE(e.expiry_date::text, 'NULL'), '.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_expired

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_DISCREPANCY', 'KYC_VERIFICATION_STATUS_DISCREPANCY',
      concat(
        'Marked verified, but the recorded expiry no longer supports it. Expiry ',
        COALESCE(e.expiry_date::text, 'none'),
        ', verified ', e.verification_date::date::text, '.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_discrepancy

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_INCOMPLETE', 'KYC_VERIFICATION_GAP',
      concat('Verification did not complete. Status ', e.verification_status, '.'),
      'MEDIUM', 'KYC_GAP', 3
    FROM evaluated_rules e
    WHERE e.is_gap

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'KYC_VERIFICATION_UNRESOLVED_IDENTITY', 'KYC_IDENTITY_UNRESOLVED',
      'This verification event sits on a source customer record whose golden customer is not confirmed. The report still has to include it.',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  -- Keep one finding per record. Both detection functions use this same ranking.
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_kyc_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_kyc$;

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'Apply the eight rules to one batch of KYC verification events, returning only the most severe finding per record. A NULL batch checks every batch at its latest version.';

-- Section 4: the ten AML screening rules

DROP FUNCTION IF EXISTS silver.detect_aml_screening_issues(varchar, date);

CREATE OR REPLACE FUNCTION silver.detect_aml_screening_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_aml$
  WITH staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_screening_reference))
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_screening_reference) AS source_screening_reference,
      btrim(raw.source_customer_reference) AS source_customer_reference,
      raw.screening_type,
      raw.screening_date,
      raw.screening_result,
      raw.match_score,
      COALESCE(raw.review_required_flag, false) AS review_required_flag
    FROM bronze.raw_aml_screening raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_screening_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      staged.screening_type IN ('SANCTIONS', 'PEP', 'WATCHLIST', 'ADVERSE_MEDIA') AS type_is_known,
      staged.screening_result IN (
        'CLEAR', 'POTENTIAL_MATCH', 'CONFIRMED_MATCH', 'FALSE_POSITIVE'
      ) AS result_is_known,
      staged.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH') AS result_is_alert
    FROM staged
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'AML', staged.source_system_id, staged.source_screening_reference, p_batch_id
    ) identity
  ),
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- No hit but flagged for review, with a score below the alert band: contradictory state.
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.review_required_flag
        AND COALESCE(evaluated.match_score, 0) < 0.7500
      ) AS is_clear_with_review,
      -- No hit but carrying an alert-band score: contradictory state.
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.match_score IS NOT NULL
        AND evaluated.match_score >= 0.7500
      ) AS is_clear_with_alert_score,
      -- An alert that was not flagged for review: contradictory state.
      (
        evaluated.result_is_alert
        AND NOT evaluated.review_required_flag
      ) AS is_review_flag_missing
    FROM evaluated
  ),
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'AML_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'AML_SUBJECT_MISSING' AS issue_type,
      'This screening event has neither a golden customer nor a source customer record, so it carries no subject reference.' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'AML_IDENTITY_LINK_MISMATCH', 'AML_IDENTITY_MISMATCH',
      'The golden customer and the source customer record on this screening event are not the same confirmed identity.',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'screening_type', 'AML_SCREENING_TYPE_INVALID', 'AML_SCREENING_TYPE_INVALID',
      concat('Screening type ', COALESCE(e.screening_type, 'NULL'), ' is not a recognised screening type.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_SCREENING_RESULT_INVALID', 'AML_SCREENING_RESULT_INVALID',
      concat('Screening result ', COALESCE(e.screening_result, 'NULL'), ' is not a recognised screening result.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.result_is_known

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_REVIEW_FLAG_INCONSISTENT', 'AML_REVIEW_FLAG_MISSING',
      concat(
        'Screening result ', e.screening_result,
        ' is an alert but review_required_flag is false. A suspected hit has to be reviewed.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_review_flag_missing

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_REVIEW_REQUIRED', 'AML_SCREENING_ALERT',
      concat(
        'Screening result ', e.screening_result,
        ', similarity ', COALESCE(e.match_score::text, 'NULL'),
        '. This is an alert that needs investigation, not a confirmed problem.'
      ),
      'MEDIUM', NULL::varchar, 2
    FROM evaluated_rules e
    WHERE e.result_is_alert

    UNION ALL
    SELECT
      e.*,
      'review_required_flag', 'AML_CLEAR_SCREENING_WITH_REVIEW', 'AML_STATUS_DISCREPANCY',
      concat(
        'Result is no match but review is required, with a similarity below the alert band: ',
        COALESCE(e.match_score::text, 'NULL'), '。'
      ),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_review

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT', 'AML_STATUS_DISCREPANCY',
      concat('Result is no match yet it carries an alert-band similarity of ', e.match_score::text, '.'),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_alert_score

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_OUT_OF_RANGE', 'AML_MATCH_SCORE_INVALID',
      concat('Similarity ', e.match_score::text, ' is outside the valid range 0.0000 to 1.0000.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.match_score IS NOT NULL
      AND (e.match_score < 0 OR e.match_score > 1)

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_MISSING', 'AML_MATCH_SCORE_MISSING',
      'An alert is reported with no similarity score, so the strength of the hit cannot be judged.',
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.result_is_alert
      AND e.match_score IS NULL

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'AML_SCREENING_UNRESOLVED_IDENTITY', 'AML_IDENTITY_UNRESOLVED',
      'This screening event sits on a source customer record whose golden customer is not confirmed. The report still has to include it.',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_screening_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_aml$;

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'Apply the ten rules to one batch of AML screening events, returning only the most severe finding per record. A NULL batch checks every batch at its latest version.';

-- Section 5: rule to case-type mapping, the single source for the reporting rule

CREATE SEQUENCE IF NOT EXISTS silver.compliance_case_seed;

-- The report requires a reportable KYC gap, identity mismatch or status discrepancy to open
-- one of KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY.
-- This function is where that requirement lands, so the mapping changes without touching the rules.
-- A NULL result means the rule stays a quality record, for example the LOW unresolved identity.
CREATE OR REPLACE FUNCTION silver.compliance_rule_case_type(
  p_rule_name varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $rule_case_type$
  SELECT CASE p_rule_name
    WHEN 'KYC_VERIFICATION_INCOMPLETE' THEN 'KYC_GAP'
    WHEN 'KYC_VERIFICATION_EXPIRED' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_VERIFICATION_STATUS_DISCREPANCY' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_REVIEW_REQUIRED' THEN 'AML_SCREENING_REVIEW'
    WHEN 'AML_REVIEW_FLAG_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_WITH_REVIEW' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    ELSE NULL
  END;
$rule_case_type$;

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  'The single rule-to-case-type mapping. A NULL result means the rule stays a quality record and opens no case.';

-- Section 6: finding registration

-- Register one finding as a Silver data quality issue.
--
-- The issue key is derived from batch, rule and record, so a rerun updates that one row
-- instead of adding another. The issue starts OPEN and is resolved by
-- 05_create_case_processing.sql once the rules stop reporting it.
-- Returns the case type for that rule, for the case-opening step to use.
CREATE OR REPLACE FUNCTION silver.register_compliance_finding(
  p_batch_id varchar,
  p_source_system_id varchar,
  p_entity_name varchar,
  p_record_reference varchar,
  p_record_version_reference varchar,
  p_attribute_name varchar,
  p_rule_name varchar,
  p_issue_type varchar,
  p_issue_description text,
  p_severity varchar,
  p_rule_case_type varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $register_finding$
DECLARE
  v_issue_id varchar(50);
  v_case_type varchar(50);
BEGIN
  v_issue_id := 'DQ-KYCAML-' || upper(
    substr(
      md5(concat_ws(':', p_batch_id, p_rule_name, p_entity_name, p_record_reference)),
      1,
      16
    )
  );

  v_case_type := silver.compliance_rule_case_type(p_rule_name);

  -- The case itself is opened by 05_create_case_processing.sql, so no case reference is
  -- written here, which keeps this file independent of the next one.
  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, batch_id, source_system_id, verification_case_id,
    validation_run_id, data_layer, entity_name, record_reference,
    record_version_reference, attribute_name, rule_name, rule_version,
    issue_type, issue_description, severity, detected_at, resolved_at, issue_status
  )
  VALUES (
    v_issue_id, p_batch_id, p_source_system_id, NULL,
    'KYC-AML-M5-' || p_batch_id, 'SILVER', p_entity_name, p_record_reference,
    p_record_version_reference, p_attribute_name, p_rule_name, '1.0',
    p_issue_type, left(p_issue_description, 1000), p_severity,
    clock_timestamp(), NULL, 'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    attribute_name = EXCLUDED.attribute_name,
    issue_type = EXCLUDED.issue_type,
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    issue_status = 'OPEN';

  RETURN v_case_type;
END;
$register_finding$;

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Register one validation finding as a data quality issue and return the case type for its rule.';

-- Issues are located and closed by validation batch, rule and record, so that path is indexed.
CREATE INDEX IF NOT EXISTS ix_data_quality_issue_run_record
  ON silver.data_quality_issue (validation_run_id, rule_name, record_reference);

-- <<< END SOURCE FILE: sql/module5_guanbo/04_create_kyc_aml_validation.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/05_create_case_processing.sql

-- PostgreSQL 15+
-- Member 5: opening cases and moving their status, for verification cases and AML cases.
-- Two rules: a reportable finding opens its case, and a repeated finding reuses the open case;
-- case status has to agree with the closing timestamp, and a case closes only once cleared.
-- An AML alert is only a suspicion, so its case is a review, not a conclusion.

-- Returns the verification case for a KYC finding, opening one when none exists.
-- The shared find-or-open step used by both case-specific functions.
--
-- Three steps: look for a case by subject and case type, reuse it when found, otherwise
-- derive an identifier and insert. The identifier is derived from event and case type, so a
-- repeated detection lands on the same row. Returns the case id and trigger type.
CREATE OR REPLACE FUNCTION silver.find_or_open_case(
  p_entity varchar,
  p_case_type varchar,
  p_record_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar,
  p_default_batch varchar DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $find_or_open$
DECLARE
  v_customer_id varchar(50);
  v_source_record_id varchar(50);
  v_screening_id varchar(50);
  v_customer_reference varchar(100);
  v_screening_type varchar(50);
  v_open_at timestamp;
  v_trigger_type varchar(50);
  v_table varchar;
  v_id_column varchar;
  v_prefix varchar;
  v_case_id varchar(50);
BEGIN
  -- Read the subject, and decide which case table is written.
  IF p_entity = 'KYC' THEN
    SELECT verification.customer_id, verification.source_customer_record_id
    INTO v_customer_id, v_source_record_id
    FROM silver.kyc_verification_record verification
    WHERE verification.kyc_verification_id = p_record_id;

    v_table := 'silver.special_verification_case';
    v_id_column := 'verification_case_id';
    v_prefix := 'SVCR-';

    v_trigger_type := CASE
      WHEN v_customer_id IS NOT NULL THEN 'GOLDEN_CUSTOMER'
      ELSE 'SOURCE_CUSTOMER_RECORD'
    END;
    -- Opened at the event's business time, so a rerun cannot inflate the case age.
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_KYC_VERIFICATION_EVENT'
    ), clock_timestamp());
  ELSIF p_entity = 'AML' THEN
    SELECT
      screening.customer_id,
      screening.source_customer_record_id,
      screening.source_screening_reference,
      screening.screening_type
    INTO v_customer_id, v_source_record_id, v_customer_reference, v_screening_type
    FROM silver.aml_screening_result screening
    WHERE screening.aml_screening_id = p_record_id;

    v_screening_id := p_record_id;
    v_table := 'silver.aml_case';
    v_id_column := 'aml_case_id';
    v_prefix := 'AMLC-';

    v_trigger_type := CASE v_screening_type
      WHEN 'SANCTIONS' THEN 'SANCTIONS_SCREENING'
      WHEN 'PEP' THEN 'PEP_SCREENING'
      WHEN 'WATCHLIST' THEN 'WATCHLIST_SCREENING'
      WHEN 'ADVERSE_MEDIA' THEN 'ADVERSE_MEDIA_SCREENING'
      ELSE 'SCREENING_ALERT'
    END;
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_AML_SCREENING_EVENT'
    ), clock_timestamp());
  ELSE
    RAISE EXCEPTION 'Unsupported entity %: expected KYC or AML', p_entity;
  END IF;

  -- One case per subject and case type.
  EXECUTE format(
    'SELECT %I FROM %s
     WHERE case_type = $1
       AND customer_id IS NOT DISTINCT FROM $2
       AND source_customer_record_id IS NOT DISTINCT FROM $3
     ORDER BY opened_at DESC, %I DESC
     LIMIT 1',
    v_id_column, v_table, v_id_column
  )
  INTO v_case_id
  USING p_case_type, v_customer_id, v_source_record_id;

  IF v_case_id IS NULL THEN
    v_case_id := v_prefix || upper(substr(md5(p_record_id || ':' || p_case_type), 1, 16));

    -- Case severity uses the case scale, so BLOCKING never appears: that belongs to data issues.
    IF p_entity = 'KYC' THEN
      INSERT INTO silver.special_verification_case (
        verification_case_id, customer_id, source_customer_record_id, match_id,
        kyc_verification_id, assigned_user_id, case_type, trigger_type,
        case_reason, case_status, severity, opened_at, resolved_at, resolution_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, NULL,
        p_record_id, NULL, p_case_type, v_trigger_type,
        left(concat(p_rule_name, ': ', p_issue_description), 1000),
        'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'CRITICAL'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (verification_case_id) DO NOTHING;
    ELSE
      -- AML risk tops out at HIGH, so BLOCKING maps to HIGH rather than CRITICAL.
      INSERT INTO silver.aml_case (
        aml_case_id, customer_id, source_customer_record_id, aml_screening_id,
        assigned_user_id, trigger_type, trigger_reference, case_type,
        case_status, risk_level, opened_at, closed_at, case_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, v_screening_id,
        NULL, v_trigger_type,
        left(concat(p_rule_name, ': ', v_customer_reference), 150),
        p_case_type, 'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'HIGH'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (aml_case_id) DO NOTHING;
    END IF;

    RAISE NOTICE 'Opened case % (% / %)', v_case_id, p_case_type, p_record_id;
  ELSE
    RAISE NOTICE 'Reused case % (% / %)', v_case_id, p_case_type, p_record_id;
  END IF;

  RETURN jsonb_build_object('case_id', v_case_id, 'trigger_type', v_trigger_type);
END;
$find_or_open$;

COMMENT ON FUNCTION silver.find_or_open_case(varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Shared find-or-open step: one case per subject and case type, reused when it already exists. Used by both KYC and AML.';

-- Verification case: wraps the shared step and returns the id, which is written back to the issue.
CREATE OR REPLACE FUNCTION silver.find_or_open_verification_case(
  p_case_type varchar,
  p_kyc_verification_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_verification_case$
  SELECT silver.find_or_open_case(
    'KYC', p_case_type, p_kyc_verification_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_verification_case$;

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open a verification case and return its identifier. One case per verification event and case type.';

-- AML case: the issue table has no AML column to write back to, so nothing is returned.
CREATE OR REPLACE FUNCTION silver.find_or_open_aml_case(
  p_case_type varchar,
  p_aml_screening_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_aml_case$
  SELECT silver.find_or_open_case(
    'AML', p_case_type, p_aml_screening_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_aml_case$;

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open an AML investigation case and return its identifier. Reuse works as for verification cases.';

-- Dispatch a finding to the right case-opening function.
-- KYC returns a verification case id; AML returns NULL, since the issue table only links a verification case.
CREATE OR REPLACE FUNCTION silver.resolve_compliance_case(
  p_entity_name varchar,
  p_case_type varchar,
  p_record_reference varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $resolve_case$
BEGIN
  IF p_entity_name = 'KYC_VERIFICATION_RECORD' THEN
    RETURN silver.find_or_open_verification_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
  ELSIF p_entity_name = 'AML_SCREENING_RESULT' THEN
    PERFORM silver.find_or_open_aml_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
    RETURN NULL;
  END IF;

  RAISE EXCEPTION 'Unsupported compliance entity %', p_entity_name;
END;
$resolve_case$;

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'Opens or reuses the case for one finding and returns the verification case link expected by silver.data_quality_issue.';

-- Open or reuse a case for every open finding and write back the KYC case id. Safe to rerun.
CREATE OR REPLACE PROCEDURE silver.publish_compliance_cases(
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $publish_cases$
DECLARE
  v_open_issues integer;
  v_linked_issues integer := 0;
BEGIN
  -- The issue table holds the source reference while the case functions address the published
  -- record by its key, so the key is resolved here first.
  DROP TABLE IF EXISTS tmp_compliance_case_issue;
  CREATE TEMP TABLE tmp_compliance_case_issue ON COMMIT DROP AS
  SELECT
    issue.data_quality_issue_id,
    issue.batch_id,
    issue.record_reference AS source_record_reference,
    COALESCE(
      verification.kyc_verification_id,
      screening.aml_screening_id
    ) AS published_record_id,
    issue.entity_name,
    issue.rule_name,
    issue.issue_description,
    issue.severity,
    -- The rule-to-case mapping comes from 04_create_kyc_aml_validation.sql;
    -- a rule without a mapping stays a quality record.
    silver.compliance_rule_case_type(issue.rule_name) AS case_type
  FROM silver.data_quality_issue issue
  LEFT JOIN silver.kyc_verification_record verification
    ON verification.source_system_id = issue.source_system_id
   AND verification.source_kyc_reference = issue.record_reference
  LEFT JOIN silver.aml_screening_result screening
    ON screening.source_system_id = issue.source_system_id
   AND screening.source_screening_reference = issue.record_reference
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
  ORDER BY issue.batch_id, issue.rule_name, issue.record_reference;
  SELECT count(*)::integer INTO v_open_issues FROM tmp_compliance_case_issue;
  IF EXISTS (
    SELECT 1
    FROM tmp_compliance_case_issue case_issue
    WHERE case_issue.published_record_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'A finding refers to an event that was withheld from Silver, so it has no case: %',
      (
        SELECT string_agg(case_issue.source_record_reference, ', ')
        FROM tmp_compliance_case_issue case_issue
        WHERE case_issue.published_record_id IS NULL
      );
  END IF;
  IF v_open_issues > 0 THEN
    UPDATE silver.data_quality_issue issue
    SET verification_case_id = silver.resolve_compliance_case(
      case_issue.entity_name,
      case_issue.case_type,
      case_issue.published_record_id,
      case_issue.rule_name,
      case_issue.issue_description,
      case_issue.severity
    )
    FROM tmp_compliance_case_issue case_issue
    WHERE issue.data_quality_issue_id = case_issue.data_quality_issue_id
      -- A rule with no case mapping opens nothing and writes nothing back.
      AND case_issue.case_type IS NOT NULL;
    GET DIAGNOSTICS v_linked_issues = ROW_COUNT;
  END IF;
  RAISE NOTICE 'Compliance case publication: % open findings processed, % linked',
    v_open_issues,
    v_linked_issues;
END;
$publish_cases$;

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'Opens or reuses the compliance case for every open KYC/AML finding and links KYC findings to their verification case.';

-- Reconcile case status against current evidence: findings the rules no longer report are resolved;
-- a verification case whose last open finding cleared becomes RESOLVED; an AML case whose alert
-- no longer stands becomes CLOSED; a case that still has an open finding stays open so its age accrues.
CREATE OR REPLACE PROCEDURE silver.progress_compliance_cases(
  p_reference_date date DEFAULT current_date,
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $progress_cases$
DECLARE
  v_resolved_issues integer;
  v_resolved_verification_cases integer;
  v_closed_aml_cases integer;
BEGIN
  IF p_reference_date IS NULL THEN
    RAISE EXCEPTION 'A reference date is required to progress compliance cases';
  END IF;

  DROP TABLE IF EXISTS tmp_current_finding;

  CREATE TEMP TABLE tmp_current_finding ON COMMIT DROP AS
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_kyc_verification_issues(NULL::varchar, p_reference_date) finding
  UNION
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_aml_screening_issues(NULL::varchar, p_reference_date) finding;

  UPDATE silver.data_quality_issue issue
  SET
    resolved_at = clock_timestamp(),
    issue_status = 'RESOLVED'
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = issue.record_reference
        AND finding.rule_name = issue.rule_name
    );

  GET DIAGNOSTICS v_resolved_issues = ROW_COUNT;

  UPDATE silver.special_verification_case investigation
  SET
    case_status = 'RESOLVED',
    resolved_at = clock_timestamp(),
    resolution_outcome = left(
      concat(
        'All linked findings cleared by the Member 5 validation rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND EXISTS (
      SELECT 1
      FROM silver.data_quality_issue linked_issue
      WHERE linked_issue.verification_case_id = investigation.verification_case_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM silver.data_quality_issue open_issue
      WHERE open_issue.verification_case_id = investigation.verification_case_id
        AND open_issue.issue_status = 'OPEN'
    );

  GET DIAGNOSTICS v_resolved_verification_cases = ROW_COUNT;

  UPDATE silver.aml_case investigation
  SET
    case_status = 'CLOSED',
    closed_at = clock_timestamp(),
    case_outcome = left(
      concat(
        'Screening alert reviewed; no finding remained open under the Member 5 rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND investigation.aml_screening_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = investigation.aml_screening_id
    );

  GET DIAGNOSTICS v_closed_aml_cases = ROW_COUNT;

  RAISE NOTICE
    'Case progression at %: % findings resolved, % verification cases resolved, % AML cases closed',
    p_reference_date,
    v_resolved_issues,
    v_resolved_verification_cases,
    v_closed_aml_cases;
END;
$progress_cases$;

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'Resolves findings that the current rules no longer produce and closes the cases whose findings are all cleared.';

-- <<< END SOURCE FILE: sql/module5_guanbo/05_create_case_processing.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/06_create_exception_fact.sql

-- PostgreSQL 15+
-- Member 5: the accumulating snapshot fact for compliance exceptions, one row per source case.
-- Rules: exactly one case reference per row, agreeing with the source type; each case appears
-- once; customer_key stays null while identity is unresolved; age runs to closing or the as-of date.

-- Fix for two unique indexes in the shared setup. Each row fills one case reference and leaves
-- the other null, and PostgreSQL treats nulls in a unique index as distinct, so only one row of
-- each type could be inserted. Partial indexes keep both the nulls and the one-row-per-case rule.
DO $fact_indexes$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_index index_definition
    JOIN pg_class table_definition
      ON table_definition.oid = index_definition.indrelid
    JOIN pg_namespace table_schema
      ON table_schema.oid = table_definition.relnamespace
    WHERE table_schema.nspname = 'gold'
      AND table_definition.relname = 'fact_compliance_exception'
      AND index_definition.indisunique
      AND NOT index_definition.indpred IS NOT NULL
      AND index_definition.indnatts = 1
      AND index_definition.indkey[0] IN (
        (SELECT attnum FROM pg_attribute
          WHERE attrelid = table_definition.oid AND attname = 'verification_case_id'),
        (SELECT attnum FROM pg_attribute
          WHERE attrelid = table_definition.oid AND attname = 'aml_case_id')
      )
  ) THEN
    DROP INDEX IF EXISTS gold.fact_compliance_exception_index_14;
    DROP INDEX IF EXISTS gold.fact_compliance_exception_index_15;

    CREATE UNIQUE INDEX fact_compliance_exception_index_14
      ON gold.fact_compliance_exception (verification_case_id)
      WHERE verification_case_id IS NOT NULL;

    CREATE UNIQUE INDEX fact_compliance_exception_index_15
      ON gold.fact_compliance_exception (aml_case_id)
      WHERE aml_case_id IS NOT NULL;

    RAISE NOTICE 'Rebuilt fact_compliance_exception case indexes as partial unique indexes';
  ELSE
    RAISE NOTICE 'fact_compliance_exception case indexes already allow null case references';
  END IF;
END
$fact_indexes$;

CREATE OR REPLACE FUNCTION gold.compliance_exception_fact_id(
  p_exception_source_type varchar,
  p_case_id varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $fact_id$
  SELECT CASE
    WHEN p_case_id IS NULL OR p_case_id = '' THEN NULL
    WHEN p_exception_source_type = 'VERIFICATION'
      THEN 'FCE-V-' || upper(substr(md5('VERIFICATION:' || p_case_id), 1, 20))
    WHEN p_exception_source_type = 'AML'
      THEN 'FCE-A-' || upper(substr(md5('AML:' || p_case_id), 1, 20))
    ELSE NULL
  END;
$fact_id$;

COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  'Deterministic exception fact key for an originating case, so refreshing a case updates its existing fact row.';

CREATE OR REPLACE PROCEDURE gold.refresh_compliance_exception_fact(
  p_as_of_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $refresh_fact$
DECLARE
  v_open_cases integer;
  v_current_rows integer;
  v_removed_rows integer;
  v_verification_rows integer;
  v_aml_rows integer;
BEGIN
  IF p_as_of_date IS NULL THEN
    RAISE EXCEPTION 'An as-of date is required to calculate days_open';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM silver.special_verification_case investigation
    WHERE investigation.resolved_at IS NOT NULL
      AND investigation.resolved_at::date > p_as_of_date
  ) THEN
    RAISE WARNING
      'A verification case is resolved after the as-of date %; days_open for it will be reported as zero',
      p_as_of_date;
  END IF;

  SELECT
    count(*) FILTER (WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')),
    count(*)::integer
  INTO v_open_cases, v_verification_rows
  FROM silver.special_verification_case investigation;

  SELECT count(*)::integer
  INTO v_aml_rows
  FROM silver.aml_case investigation;

  DROP TABLE IF EXISTS tmp_compliance_exception_fact;

  -- Both case types projected into one fact table.
  --
  -- This was two UNION ALL branches, each repeating the status mapping, the customer key
  -- lookup, the age calculation and the closing date. Writing one rule twice invites fixing
  -- one copy and missing the other, so UNION ALL now only aligns the columns.
  CREATE TEMP TABLE tmp_compliance_exception_fact ON COMMIT DROP AS
  WITH exception_case AS (
    SELECT
      'VERIFICATION' AS source_type,
      investigation.verification_case_id AS verification_case_id,
      NULL::varchar AS aml_case_id,
      investigation.customer_id,
      investigation.case_type,
      investigation.case_status,
      investigation.severity,
      investigation.opened_at,
      investigation.resolved_at AS closed_at
    FROM silver.special_verification_case investigation

    UNION ALL

    SELECT
      'AML',
      NULL::varchar,
      investigation.aml_case_id,
      investigation.customer_id,
      investigation.case_type,
      investigation.case_status,
      investigation.risk_level,
      investigation.opened_at,
      investigation.closed_at
    FROM silver.aml_case investigation
  )
  SELECT
    gold.compliance_exception_fact_id(
      exception_case.source_type,
      COALESCE(exception_case.verification_case_id, exception_case.aml_case_id)
    ) AS exception_fact_id,
    dimension.customer_key,
    exception_case.verification_case_id,
    exception_case.aml_case_id,
    exception_case.source_type AS exception_source_type,
    exception_case.case_type AS exception_type,
    -- Exception status is the fact's own view of the case, mapped from the case status.
    CASE exception_case.case_status
      WHEN 'OPEN' THEN 'OPEN'
      WHEN 'IN_REVIEW' THEN 'IN_REVIEW'
      WHEN 'RESOLVED' THEN 'RESOLVED'
      ELSE 'CLOSED'
    END AS exception_status,
    exception_case.severity,
    exception_case.opened_at::date AS opened_date,
    exception_case.closed_at::date AS resolved_date,
    p_as_of_date AS as_of_date,
    -- Age runs from opening to closing, or to the as-of date while open, and is capped there
    -- so a report cannot claim an age longer than its period. resolved_date keeps the real date.
    GREATEST(
      LEAST(COALESCE(exception_case.closed_at::date, p_as_of_date), p_as_of_date)
        - exception_case.opened_at::date,
      0
    ) AS days_open,
    clock_timestamp() AS last_updated_at
  FROM exception_case
  LEFT JOIN LATERAL (
    SELECT customer_dimension.customer_key
    FROM gold.dim_customer customer_dimension
    WHERE customer_dimension.customer_id = exception_case.customer_id
      AND customer_dimension.current_flag
    ORDER BY customer_dimension.effective_from DESC, customer_dimension.customer_key DESC
    LIMIT 1
  ) dimension ON true;

  INSERT INTO gold.fact_compliance_exception (
    exception_fact_id,
    customer_key,
    verification_case_id,
    aml_case_id,
    exception_source_type,
    exception_type,
    exception_status,
    severity,
    opened_date,
    resolved_date,
    as_of_date,
    days_open,
    last_updated_at
  )
  SELECT
    staged.exception_fact_id,
    staged.customer_key,
    staged.verification_case_id,
    staged.aml_case_id,
    staged.exception_source_type,
    staged.exception_type,
    staged.exception_status,
    staged.severity,
    staged.opened_date,
    staged.resolved_date,
    staged.as_of_date,
    staged.days_open,
    staged.last_updated_at
  FROM tmp_compliance_exception_fact staged
  ON CONFLICT (exception_fact_id) DO UPDATE SET
    customer_key = EXCLUDED.customer_key,
    exception_type = EXCLUDED.exception_type,
    exception_status = EXCLUDED.exception_status,
    severity = EXCLUDED.severity,
    opened_date = EXCLUDED.opened_date,
    resolved_date = EXCLUDED.resolved_date,
    as_of_date = EXCLUDED.as_of_date,
    days_open = EXCLUDED.days_open,
    last_updated_at = EXCLUDED.last_updated_at;

  -- A stale fact row whose case is gone would break the one-row-per-case rule, so it is removed.
  DELETE FROM gold.fact_compliance_exception fact
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.special_verification_case investigation
    WHERE investigation.verification_case_id = fact.verification_case_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM silver.aml_case investigation
    WHERE investigation.aml_case_id = fact.aml_case_id
  );

  GET DIAGNOSTICS v_removed_rows = ROW_COUNT;

  RAISE NOTICE
    'Compliance exception fact refreshed at %: % verification cases (% open), % AML cases, % stale facts removed',
    p_as_of_date,
    v_verification_rows,
    v_open_cases,
    v_aml_rows,
    v_removed_rows;
END;
$refresh_fact$;

COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  'Rebuilds the accumulating compliance exception fact for both case types, updating open cases in place and recalculating days_open to the as-of date.';

-- <<< END SOURCE FILE: sql/module5_guanbo/06_create_exception_fact.sql

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/07_create_compliance_reporting_views.sql

-- PostgreSQL 15+
-- Member 5: compliance exception reporting. Defines the exception report, the summary and the
-- lineage view, plus the customer KYC status function that applies the report's rule.
-- Plain views rather than materialised ones, so a report reads the latest refresh with no extra step.

-- The report's KYC status rule: VERIFIED only when every required verification succeeded and is
-- unexpired with no unresolved relevant exception; otherwise INCOMPLETE, REVIEW_REQUIRED or UNKNOWN.
-- One row per golden customer, evaluated at a given date, which is why it is a function.
CREATE OR REPLACE FUNCTION silver.customer_kyc_status(
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  customer_id varchar,
  customer_full_name varchar,
  verification_count integer,
  latest_verification_date timestamp,
  latest_verification_status varchar,
  latest_expiry_date date,
  reusable_verification_count integer,
  aml_alert_count integer,
  open_exception_count integer,
  kyc_status varchar
)
LANGUAGE sql
STABLE
AS $kyc_status$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  verification AS (
    SELECT
      record.customer_id,
      count(*)::integer AS verification_count,
      max(record.verification_date) AS latest_verification_date,
      count(*) FILTER (
        WHERE record.verification_status = 'VERIFIED'
          AND (record.expiry_date IS NULL OR record.expiry_date >= reference_date.as_of_date)
      )::integer AS reusable_verification_count
    FROM silver.kyc_verification_record record
    CROSS JOIN reference_date
    WHERE record.customer_id IS NOT NULL
    GROUP BY record.customer_id
  ),
  latest_verification AS (
    SELECT DISTINCT ON (record.customer_id)
      record.customer_id,
      record.verification_status,
      record.expiry_date
    FROM silver.kyc_verification_record record
    WHERE record.customer_id IS NOT NULL
    ORDER BY
      record.customer_id,
      record.verification_date DESC,
      record.kyc_verification_id DESC
  ),
  screening AS (
    SELECT
      record.customer_id,
      count(*) FILTER (
        WHERE record.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH')
      )::integer AS aml_alert_count
    FROM silver.aml_screening_result record
    WHERE record.customer_id IS NOT NULL
    GROUP BY record.customer_id
  ),
  investigation AS (
    SELECT
      investigation_case.customer_id,
      count(*)::integer AS open_exception_count
    FROM (
      SELECT
        verification_case.customer_id,
        verification_case.case_status
      FROM silver.special_verification_case verification_case
      UNION ALL
      SELECT
        aml_case.customer_id,
        aml_case.case_status
      FROM silver.aml_case aml_case
    ) investigation_case
    WHERE investigation_case.case_status IN ('OPEN', 'IN_REVIEW')
      AND investigation_case.customer_id IS NOT NULL
    GROUP BY investigation_case.customer_id
  ),
  -- Status is computed in its own step to keep output column names from colliding with base ones.
  evaluated_customer AS (
    SELECT
      customer.customer_id,
      customer.customer_full_name,
      COALESCE(verification.verification_count, 0) AS verification_count,
      verification.latest_verification_date,
      latest_verification.verification_status,
      latest_verification.expiry_date,
      COALESCE(verification.reusable_verification_count, 0) AS reusable_verification_count,
      COALESCE(screening.aml_alert_count, 0) AS aml_alert_count,
      COALESCE(investigation.open_exception_count, 0) AS open_exception_count
    FROM silver.customer_master customer
    LEFT JOIN verification ON verification.customer_id = customer.customer_id
    LEFT JOIN latest_verification ON latest_verification.customer_id = customer.customer_id
    LEFT JOIN screening ON screening.customer_id = customer.customer_id
    LEFT JOIN investigation ON investigation.customer_id = customer.customer_id
  )
  SELECT
    evaluated_customer.customer_id::varchar,
    evaluated_customer.customer_full_name::varchar,
    evaluated_customer.verification_count,
    evaluated_customer.latest_verification_date,
    evaluated_customer.verification_status::varchar,
    evaluated_customer.expiry_date,
    evaluated_customer.reusable_verification_count,
    evaluated_customer.aml_alert_count,
    evaluated_customer.open_exception_count,
    CASE
      WHEN evaluated_customer.verification_count = 0
        AND evaluated_customer.aml_alert_count = 0
        THEN 'UNKNOWN'
      WHEN evaluated_customer.open_exception_count > 0
        THEN 'REVIEW_REQUIRED'
      WHEN evaluated_customer.reusable_verification_count > 0
        THEN 'VERIFIED'
      ELSE 'INCOMPLETE'
    END::varchar AS kyc_status
  FROM evaluated_customer;
$kyc_status$;

COMMENT ON FUNCTION silver.customer_kyc_status(date) IS
  'One row per golden customer with the report-defined KYC status at a reference date: VERIFIED, INCOMPLETE, REVIEW_REQUIRED or UNKNOWN.';

-- The exception report: one row per exception, with the originating case detail behind it.
-- Rows with an unresolved identity are kept by the left join rather than dropped.
CREATE OR REPLACE VIEW gold.vw_kyc_aml_exception_report AS
SELECT
  fact.exception_fact_id,
  fact.exception_source_type,
  fact.exception_type,
  fact.exception_status,
  fact.severity,
  fact.opened_date,
  fact.resolved_date,
  fact.as_of_date,
  fact.days_open,
  fact.customer_key,
  COALESCE(dimension.customer_id, verification_case.customer_id, aml_case.customer_id)
    AS customer_id,
  COALESCE(
    dimension.customer_full_name,
    customer.customer_full_name,
    'Unresolved identity'
  ) AS customer_name,
  fact.verification_case_id,
  fact.aml_case_id,
  COALESCE(verification_case.trigger_type, aml_case.trigger_type) AS trigger_type,
  COALESCE(verification_case.case_reason, aml_case.trigger_reference) AS case_reason,
  verification_case.kyc_verification_id,
  aml_case.aml_screening_id,
  COALESCE(verification_case.resolution_outcome, aml_case.case_outcome) AS case_outcome,
  fact.last_updated_at
FROM gold.fact_compliance_exception fact
LEFT JOIN gold.dim_customer dimension
  ON dimension.customer_key = fact.customer_key
LEFT JOIN silver.special_verification_case verification_case
  ON verification_case.verification_case_id = fact.verification_case_id
LEFT JOIN silver.aml_case aml_case
  ON aml_case.aml_case_id = fact.aml_case_id
LEFT JOIN silver.customer_master customer
  ON customer.customer_id = COALESCE(
    verification_case.customer_id,
    aml_case.customer_id
  );

COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'One row per compliance exception with its originating case detail; unresolved identities are retained rather than filtered out.';

-- The summary view: totals by customer and exception type, for the report's summary block.
CREATE OR REPLACE VIEW gold.vw_compliance_exception_summary AS
WITH customer_exception AS (
  SELECT
    COALESCE(
      dimension.customer_id,
      verification_case.customer_id,
      aml_case.customer_id
    ) AS customer_id,
    COALESCE(customer.customer_full_name, 'Unresolved identity') AS customer_name,
    fact.exception_source_type,
    fact.exception_type,
    count(*)::integer AS exception_count,
    count(*) FILTER (
      WHERE fact.exception_status IN ('OPEN', 'IN_REVIEW')
    )::integer AS open_exception_count,
    count(*) FILTER (
      WHERE fact.exception_status IN ('RESOLVED', 'CLOSED')
    )::integer AS resolved_exception_count,
    max(fact.days_open) AS longest_days_open,
    max(fact.as_of_date) AS as_of_date,
    -- Severity is a label, so the highest is taken by explicit rank: alphabetically MEDIUM beats HIGH.
    max(
      CASE fact.severity
        WHEN 'CRITICAL' THEN 4
        WHEN 'HIGH' THEN 3
        WHEN 'MEDIUM' THEN 2
        WHEN 'LOW' THEN 1
        ELSE 0
      END
    ) AS severity_rank
  FROM gold.fact_compliance_exception fact
  LEFT JOIN gold.dim_customer dimension
    ON dimension.customer_key = fact.customer_key
  LEFT JOIN silver.special_verification_case verification_case
    ON verification_case.verification_case_id = fact.verification_case_id
  LEFT JOIN silver.aml_case aml_case
    ON aml_case.aml_case_id = fact.aml_case_id
  LEFT JOIN silver.customer_master customer
    ON customer.customer_id = COALESCE(
      verification_case.customer_id,
      aml_case.customer_id
    )
  GROUP BY
    COALESCE(
      dimension.customer_id,
      verification_case.customer_id,
      aml_case.customer_id
    ),
    COALESCE(customer.customer_full_name, 'Unresolved identity'),
    fact.exception_source_type,
    fact.exception_type
)
SELECT
  customer_exception.customer_id,
  customer_exception.customer_name,
  customer_exception.exception_source_type,
  customer_exception.exception_type,
  customer_exception.exception_count,
  customer_exception.open_exception_count,
  customer_exception.resolved_exception_count,
  customer_exception.longest_days_open,
  CASE customer_exception.severity_rank
    WHEN 4 THEN 'CRITICAL'
    WHEN 3 THEN 'HIGH'
    WHEN 2 THEN 'MEDIUM'
    WHEN 1 THEN 'LOW'
    ELSE 'UNKNOWN'
  END AS highest_severity,
  customer_exception.as_of_date
FROM customer_exception;

COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  'Exception counts and longest open duration per customer, source type and exception type.';

-- The lineage view: raw Bronze record to Silver event to case to exception fact, as one chain.
CREATE OR REPLACE VIEW silver.vw_kyc_aml_exception_lineage AS
SELECT
  lineage.lineage_id,
  lineage.batch_id,
  lineage.source_record_reference AS bronze_record_reference,
  lineage.target_record_reference AS published_event_reference,
  lineage.target_entity_name,
  lineage.transformation_name,
  lineage.transformation_timestamp,
  COALESCE(
    verification_case.verification_case_id,
    aml_case.aml_case_id
  ) AS case_reference,
  COALESCE(verification_case.case_type, aml_case.case_type) AS case_type,
  gold.compliance_exception_fact_id(
    CASE
      WHEN verification_case.verification_case_id IS NOT NULL THEN 'VERIFICATION'
      ELSE 'AML'
    END,
    COALESCE(verification_case.verification_case_id, aml_case.aml_case_id)
  ) AS exception_fact_id
FROM silver.data_lineage_record lineage
LEFT JOIN silver.special_verification_case verification_case
  ON verification_case.kyc_verification_id = lineage.target_record_reference
LEFT JOIN silver.aml_case aml_case
  ON aml_case.aml_screening_id = lineage.target_record_reference
WHERE lineage.transformation_name IN (
  'PUBLISH_KYC_VERIFICATION_EVENT',
  'PUBLISH_AML_SCREENING_EVENT'
);

COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  'Traceability path from each retained Bronze KYC/AML record through its published Silver event to the compliance case and exception fact row.';

-- <<< END SOURCE FILE: sql/module5_guanbo/07_create_compliance_reporting_views.sql

-- >>> BEGIN GENERATED SECTION: Member 5 integration calls

-- Publish both supplied AML/KYC batches before Member 4 creates its dated snapshots.
CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');
CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');
CALL silver.publish_compliance_cases();
CALL silver.progress_compliance_cases(DATE '2026-09-30');
CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');

-- <<< END GENERATED SECTION: Member 5 integration calls

-- >>> BEGIN SOURCE FILE: sql/module5_guanbo/09_add_object_descriptions.sql

-- PostgreSQL 15+
-- Member 5: catalogue descriptions for every object this module owns.
--
-- Run after 00-07. Idempotent: PostgreSQL keeps one description per object, so
-- rerunning replaces rather than appends. Only this module's own objects are
-- described, so no other member's descriptions are overwritten.

-- ---------------------------------------------------------------- tables
COMMENT ON TABLE silver.kyc_verification_record IS
  'One KYC verification attempt. An event table: it records what the source system reported and is never rewritten by the review that follows. Where a record has to be superseded, a new version is inserted (source_kyc_reference plus version).';

COMMENT ON TABLE silver.special_verification_case IS
  'One case opened to follow up a reportable KYC finding. A case table: it records the decision taken about an event, so it changes over time. At most one case exists per KYC event and case type, so a repeated finding reuses the open case.';

COMMENT ON TABLE silver.aml_screening_result IS
  'One AML screening of a customer against watchlists and sanctions lists. An event table, and the counterpart of silver.kyc_verification_record. A screening result is a signal, not a conclusion: a hit is a suspected match.';

COMMENT ON TABLE silver.aml_case IS
  'One investigation opened from an AML screening alert. A case table, the counterpart of silver.special_verification_case. At most one case exists per screening event and case type.';

COMMENT ON TABLE gold.fact_compliance_exception IS
  'Accumulating snapshot fact for the KYC/AML exception report: one row per originating case, updated in place as the case moves. Dates are the reporting view of the case, so days_open can be capped at the reporting date without touching the case itself.';

-- ------------------------------------------- silver.kyc_verification_record
COMMENT ON COLUMN silver.kyc_verification_record.kyc_verification_id IS
  'Primary key, derived from the source system and the source KYC reference so that reprocessing the same record produces the same key.';
COMMENT ON COLUMN silver.kyc_verification_record.customer_id IS
  'Golden customer, once identity resolution has merged this customer. Null while the identity is unresolved, and the report keeps the row either way.';
COMMENT ON COLUMN silver.kyc_verification_record.source_customer_record_id IS
  'The Silver record for the source system''s own customer. Present even when no golden customer has been resolved.';
COMMENT ON COLUMN silver.kyc_verification_record.source_system_id IS
  'Source system this event came from, which with source_kyc_reference identifies the record.';
COMMENT ON COLUMN silver.kyc_verification_record.reviewed_by IS
  'The user who performed the verification, when the source system records one.';
COMMENT ON COLUMN silver.kyc_verification_record.source_kyc_reference IS
  'The source system''s own reference for this verification. Part of the derived primary key.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_type IS
  'The kind of check performed. An unrecognised value is reported by the KYC_VERIFICATION_TYPE_INVALID rule.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_status IS
  'Reported outcome. Read together with expiry_date: a status of VERIFIED whose expiry has passed is reported as a status discrepancy.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_date IS
  'When the verification was performed. Used with the reporting date to decide whether the record had expired by then.';
COMMENT ON COLUMN silver.kyc_verification_record.expiry_date IS
  'Date the verification stops being valid. Null means no expiry was recorded, which KYC_VERIFICATION_EXPIRY_MISSING reports.';
COMMENT ON COLUMN silver.kyc_verification_record.risk_level_at_verification IS
  'Customer risk level as it stood at verification time, kept because the current level may have moved since.';

-- ------------------------------------------ silver.special_verification_case
COMMENT ON COLUMN silver.special_verification_case.verification_case_id IS
  'Primary key, derived from the KYC event and the case type, so a repeated finding lands on the same case.';
COMMENT ON COLUMN silver.special_verification_case.customer_id IS
  'Golden customer the case concerns. Null while the identity is unresolved.';
COMMENT ON COLUMN silver.special_verification_case.source_customer_record_id IS
  'The source customer record behind the event, kept so the case can be traced even with no golden customer.';
COMMENT ON COLUMN silver.special_verification_case.match_id IS
  'The identity match that linked the source record to the golden customer, when one was used.';
COMMENT ON COLUMN silver.special_verification_case.kyc_verification_id IS
  'The KYC verification event that triggered the case.';
COMMENT ON COLUMN silver.special_verification_case.assigned_user_id IS
  'The user handling the case, when one has been assigned.';
COMMENT ON COLUMN silver.special_verification_case.case_type IS
  'Why the case exists: KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY, as the report requires.';
COMMENT ON COLUMN silver.special_verification_case.trigger_type IS
  'What opened the case, so a case can be traced back to the rule that produced it.';
COMMENT ON COLUMN silver.special_verification_case.case_reason IS
  'Human-readable reason, carried from the finding that opened the case.';
COMMENT ON COLUMN silver.special_verification_case.case_status IS
  'Open, under review, resolved and so on. A case closes only once its finding has cleared.';
COMMENT ON COLUMN silver.special_verification_case.severity IS
  'Case severity on the case scale. BLOCKING never appears here: that belongs to a data quality issue.';
COMMENT ON COLUMN silver.special_verification_case.opened_at IS
  'When the case was opened, taken from the triggering event''s business time so a rerun cannot inflate the case age.';
COMMENT ON COLUMN silver.special_verification_case.resolved_at IS
  'When the case was closed. Null while it is open, and kept in step with case_status by the progress step.';
COMMENT ON COLUMN silver.special_verification_case.resolution_outcome IS
  'What the review concluded, recorded when the case closes.';

-- ------------------------------------------------- silver.aml_screening_result
COMMENT ON COLUMN silver.aml_screening_result.aml_screening_id IS
  'Primary key, derived from the source system and the source screening reference so reprocessing is idempotent.';
COMMENT ON COLUMN silver.aml_screening_result.customer_id IS
  'Golden customer, once identity resolution has merged this customer. Null while unresolved.';
COMMENT ON COLUMN silver.aml_screening_result.source_customer_record_id IS
  'The Silver record for the source system''s own customer, present even with no golden customer.';
COMMENT ON COLUMN silver.aml_screening_result.source_system_id IS
  'Source system this screening came from.';
COMMENT ON COLUMN silver.aml_screening_result.source_screening_reference IS
  'The source system''s own reference for this screening. Part of the derived primary key.';
COMMENT ON COLUMN silver.aml_screening_result.screening_type IS
  'The list or check applied, such as sanctions or PEP. An unrecognised value is reported by AML_SCREENING_TYPE_INVALID.';
COMMENT ON COLUMN silver.aml_screening_result.screening_date IS
  'When the screening ran.';
COMMENT ON COLUMN silver.aml_screening_result.screening_result IS
  'The outcome, such as CLEAR, POTENTIAL_MATCH or CONFIRMED_MATCH. An alert without review_required_flag is reported as contradictory.';
COMMENT ON COLUMN silver.aml_screening_result.match_score IS
  'Similarity, from 0.0000 to 1.0000. A score outside that range, or an alert with no score at all, is reported.';
COMMENT ON COLUMN silver.aml_screening_result.provider_reference IS
  'The screening provider''s own reference, kept for reconciliation with the vendor.';
COMMENT ON COLUMN silver.aml_screening_result.review_required_flag IS
  'Whether a person has to review the result. Required for any alert, and not allowed for a low-scoring near miss.';

-- ---------------------------------------------------------------- silver.aml_case
COMMENT ON COLUMN silver.aml_case.aml_case_id IS
  'Primary key, derived from the screening event and the case type, so a repeated alert reuses the same case.';
COMMENT ON COLUMN silver.aml_case.customer_id IS
  'Golden customer under investigation. Null while the identity is unresolved.';
COMMENT ON COLUMN silver.aml_case.source_customer_record_id IS
  'The source customer record behind the alert.';
COMMENT ON COLUMN silver.aml_case.aml_screening_id IS
  'The screening event that raised the alert this case investigates.';
COMMENT ON COLUMN silver.aml_case.assigned_user_id IS
  'The investigator handling the case, when one has been assigned.';
COMMENT ON COLUMN silver.aml_case.trigger_type IS
  'What opened the case, so it can be traced back to the alert that produced it.';
COMMENT ON COLUMN silver.aml_case.trigger_reference IS
  'The reference of the triggering alert.';
COMMENT ON COLUMN silver.aml_case.case_type IS
  'Why the case exists, for example AML_SCREENING_REVIEW. A rule with no mapping on this table opens no case.';
COMMENT ON COLUMN silver.aml_case.case_status IS
  'Open, under investigation, closed and so on. A case closes only once its alert no longer stands.';
COMMENT ON COLUMN silver.aml_case.risk_level IS
  'Investigation risk level. Topped at HIGH, so a blocking finding maps to HIGH rather than CRITICAL.';
COMMENT ON COLUMN silver.aml_case.opened_at IS
  'When the case was opened, taken from the alert''s business time.';
COMMENT ON COLUMN silver.aml_case.closed_at IS
  'When the case was closed. Null while it is open, and kept in step with case_status.';
COMMENT ON COLUMN silver.aml_case.case_outcome IS
  'What the investigation concluded, recorded when the case closes.';

-- -------------------------------------------- gold.fact_compliance_exception
COMMENT ON COLUMN gold.fact_compliance_exception.exception_fact_id IS
  'Primary key, derived from the source type and the case identifier, so refreshing a case updates its row.';
COMMENT ON COLUMN gold.fact_compliance_exception.customer_key IS
  'Dimension key for the golden customer. Null while the identity is unresolved, which is why the report joins with a left join.';
COMMENT ON COLUMN gold.fact_compliance_exception.verification_case_id IS
  'The verification case this row reports. Filled for KYC exceptions and null for AML ones.';
COMMENT ON COLUMN gold.fact_compliance_exception.aml_case_id IS
  'The AML case this row reports. Filled for AML exceptions and null for KYC ones.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_source_type IS
  'Which case table the row came from: VERIFICATION or AML. Exactly one of the two case columns is filled to match.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_type IS
  'The kind of exception, such as KYC_GAP or AML_SCREENING_REVIEW, carried from the case type.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_status IS
  'The fact''s own view of the case state, mapped from the case status. Kept here because the fact reports state over time.';
COMMENT ON COLUMN gold.fact_compliance_exception.severity IS
  'Severity on the case scale, so the report and the case agree.';
COMMENT ON COLUMN gold.fact_compliance_exception.opened_date IS
  'Date the case was opened, which is where days_open starts counting.';
COMMENT ON COLUMN gold.fact_compliance_exception.resolved_date IS
  'Date the case was closed, or null while it is open. This is the real closing date, not the capped one.';
COMMENT ON COLUMN gold.fact_compliance_exception.as_of_date IS
  'The reporting date this row was last refreshed for. Refreshing an open case for a later date updates the same row.';
COMMENT ON COLUMN gold.fact_compliance_exception.days_open IS
  'Calendar days from opening to closing, or to as_of_date while open, capped at as_of_date so a report cannot claim an age longer than its own period.';
COMMENT ON COLUMN gold.fact_compliance_exception.last_updated_at IS
  'When the row was last refreshed, so a report can tell a fresh row from a stale one.';

-- ---------------------------------------------------------------- views
COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'The KYC/AML exception report: one row per reported exception with its originating case detail and the customer name. Cases whose identity is still unresolved are kept through a left join rather than dropped.';

COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  'Exception totals by customer and exception type, for the summary block of the report.';

COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  'Traceability for the report: each published exception followed back from the exception fact, through the case, to the Silver event and the retained Bronze record.';

-- ---------------------------------------------------------------- functions
COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  'Stable key for a KYC verification event, derived from the source system and source KYC reference so reprocessing adds no duplicate row.';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  'Stable key for an AML screening event, derived from the source system and source screening reference, as for the KYC version.';

COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  'Stable key for an exception fact row, derived from the source type and the case identifier so a refresh updates the same row.';

COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  'Resolve the source customer record and golden customer for one event. Both are null when nothing is found, which is how a caller detects an identity that is not merged yet.';

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'Apply the eight KYC verification rules to one batch, returning only the most severe finding per record. A null batch checks every batch at its latest Bronze version.';

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'Apply the ten AML screening rules to one batch, returning only the most severe finding per record. A null batch checks every batch at its latest Bronze version.';

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  'The single rule-to-case-type mapping the report requires. A null result means the rule stays a quality record and opens no case.';

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Register one finding as a Silver data quality issue and return the case type for its rule. The issue key is derived from batch, rule and record, so a rerun updates that one row.';

COMMENT ON FUNCTION silver.find_or_open_case(varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Shared find-or-open step: one case per subject and case type, reused when it already exists. Used by both the KYC and the AML case functions.';

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open the verification case for a KYC finding and return its identifier, which is written back to the data quality issue.';

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open the AML investigation case for a screening alert. Nothing is written back, because the issue table links only a verification case.';

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'Dispatch a finding to the right case function. Returns a verification case id for KYC findings and null for AML ones.';

COMMENT ON FUNCTION silver.customer_kyc_status(date) IS
  'Customer KYC status under the reporting rule: VERIFIED only when every required verification succeeded and is unexpired with no unresolved relevant exception, otherwise INCOMPLETE, REVIEW_REQUIRED or UNKNOWN. One row per golden customer, evaluated at the given date.';

-- --------------------------------------------------------------- procedures
COMMENT ON PROCEDURE silver.stage_bronze_batch(varchar, varchar) IS
  'Stage one batch''s Bronze rows and attach the identity lookup result, so the rules and the publisher share one evaluation.';

COMMENT ON PROCEDURE silver.record_event_lineage(varchar, varchar) IS
  'Record published events in the lineage table, linking each Bronze record to the Silver event it produced. Republishing adds nothing, because the lineage key is derived.';

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'Validate one batch of Bronze KYC verification rows and publish them to Silver, withholding any row that carries a blocking finding.';

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'Validate one batch of Bronze AML screening rows and publish them to Silver, withholding any row that carries a blocking finding.';

COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  'Create the minimum customer identity this module''s events reference. Existing resolutions are left untouched; only missing ones are added.';

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Batch entry point: resolve customer identity, publish the KYC and AML events to Silver, then run the rules and register the findings.';

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'Open or reuse a case for every open finding and write the verification case id back to the issue. Safe to rerun.';

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'Reconcile case status against current evidence: resolve findings the rules no longer report, close the cases they clear, and leave a case with an open finding open so its age keeps accruing.';

COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  'Refresh the exception fact for one reporting date, from both case tables. Updating an open case updates its existing row; a stale row whose case is gone is removed.';

-- <<< END SOURCE FILE: sql/module5_guanbo/09_add_object_descriptions.sql

-- >>> BEGIN SOURCE FILE: sql/module4_dan/07_run_reporting_date.sql

-- Step 7: Run Member4 for two reporting dates (2026-09-01, then 2026-09-15) and show the results.
-- Run after files 01-06 and after Module 5. Safe to rerun: 7.0 clears only Member4 data, so the same dates give the same result.
-- Dates must run oldest first: Silver keeps only the latest date, Gold keeps one snapshot per date.

-- 7.0 Clear Member4 financial and snapshot data (empty on the first run).
TRUNCATE silver.account_transaction, silver.banking_account, silver.loan, gold.fact_customer_snapshot CASCADE;
DELETE FROM silver.customer_risk_assessment;
DELETE FROM silver.data_quality_issue WHERE validation_run_id LIKE 'FIN-%';

-- 7.1 Build customer history.
CALL gold.load_dim_customer();
SELECT customer_id, customer_full_name, customer_status, effective_from, current_flag FROM gold.dim_customer ORDER BY customer_id;

-- 7.2 Day 1 (1 Sep): load into Silver and list data quality issues.
CALL silver.load_financials(DATE '2026-09-01');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-01';

-- 7.3 Day 1: acknowledge LOAN-002 (no ACCEPTED customer match).
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-01' AND issue_status = 'OPEN';

-- 7.4 Day 1: customer totals.
SELECT * FROM gold.customer_financials(DATE '2026-09-01');

-- 7.5 Day 1: assess risk and publish the 1 Sep snapshot (must happen BEFORE loading 15 Sep).
CALL gold.publish_snapshot(DATE '2026-09-01', '{"rule_name":"demo_rules","rule_version":"2","rules":[
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":0,"exposure_max":50000,"score":50,"rating":"MEDIUM","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure below 50000"},
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":50000,"exposure_max":null,"score":80,"rating":"HIGH","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure 50000 or more"},
 {"kyc_status":"VERIFIED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":20,"rating":"LOW","kyc_risk_rating":"LOW","aml_risk_rating":"LOW","reason":"KYC verified; AML screening clear"},
 {"kyc_status":"VERIFIED","aml_risk_level":"POTENTIAL_MATCH","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; AML potential match"},
 {"kyc_status":"VERIFIED","aml_risk_level":"MEDIUM","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; open AML case rated MEDIUM"},
 {"kyc_status":"VERIFIED","aml_risk_level":"HIGH","exposure_min":0,"exposure_max":null,"score":90,"rating":"HIGH","kyc_risk_rating":"LOW","aml_risk_rating":"HIGH","reason":"KYC verified; open AML case rated HIGH"},
 {"kyc_status":"EXPIRED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC expired; AML screening clear"},
 {"kyc_status":"MISSING_DOCUMENT","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC document missing; AML screening clear"}]}');

-- 7.6 Day 2 (15 Sep): load, acknowledge, check totals.
CALL silver.load_financials(DATE '2026-09-15');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-15';
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-15' AND issue_status = 'OPEN';
SELECT * FROM gold.customer_financials(DATE '2026-09-15');

-- 7.7 Day 2: publish the 15 Sep snapshot.
CALL gold.publish_snapshot(DATE '2026-09-15', '{"rule_name":"demo_rules","rule_version":"2","rules":[
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":0,"exposure_max":50000,"score":50,"rating":"MEDIUM","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure below 50000"},
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":50000,"exposure_max":null,"score":80,"rating":"HIGH","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure 50000 or more"},
 {"kyc_status":"VERIFIED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":20,"rating":"LOW","kyc_risk_rating":"LOW","aml_risk_rating":"LOW","reason":"KYC verified; AML screening clear"},
 {"kyc_status":"VERIFIED","aml_risk_level":"POTENTIAL_MATCH","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; AML potential match"},
 {"kyc_status":"VERIFIED","aml_risk_level":"MEDIUM","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; open AML case rated MEDIUM"},
 {"kyc_status":"VERIFIED","aml_risk_level":"HIGH","exposure_min":0,"exposure_max":null,"score":90,"rating":"HIGH","kyc_risk_rating":"LOW","aml_risk_rating":"HIGH","reason":"KYC verified; open AML case rated HIGH"},
 {"kyc_status":"EXPIRED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC expired; AML screening clear"},
 {"kyc_status":"MISSING_DOCUMENT","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC document missing; AML screening clear"}]}');

-- 7.8 Reports (now two dates).
SELECT * FROM gold.v_portfolio_health ORDER BY snapshot_date;
SELECT * FROM gold.v_portfolio_risk_distribution ORDER BY snapshot_date, risk_rating;
SELECT * FROM gold.v_customer_risk_profile ORDER BY customer_id, snapshot_date;

-- 7.9 What changed between the two dates.
SELECT coalesce(a.customer_full_name, b.customer_full_name) AS customer,
       a.risk_rating AS rating_0901, b.risk_rating AS rating_0915,
       a.total_debt AS debt_0901, b.total_debt AS debt_0915, b.assessment_reason AS reason_0915
FROM (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-01') a
FULL JOIN (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-15') b USING (customer_id)
WHERE a.risk_rating IS DISTINCT FROM b.risk_rating OR a.total_debt IS DISTINCT FROM b.total_debt
ORDER BY 1;

-- <<< END SOURCE FILE: sql/module4_dan/07_run_reporting_date.sql

-- >>> BEGIN SOURCE FILE: sql/module6_sunny/01_quality_findings.sql

-- Member 6: read-only data-quality monitoring for PostgreSQL 15+.
-- Run after 00_shared_setup/00-49; Bronze and Silver may still be empty.
-- Each row is one rule failure for one record version. No source row is changed.

CREATE OR REPLACE VIEW silver.vw_member6_quality_findings AS
WITH raw_customers AS (
  SELECT 'RAW_CRM_CUSTOMER'::text AS entity_name,
         'CRM'::text AS expected_source,
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_crm_customer
  UNION ALL
  SELECT 'RAW_LENDING_CUSTOMER', 'LEND',
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_lending_customer
  UNION ALL
  SELECT 'RAW_AML_KYC_CUSTOMER', 'AMLKYC',
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_aml_kyc_customer
)
SELECT
  'BRONZE'::text AS data_layer,
  'CDC_CHANGE_EVENT'::text AS entity_name,
  c.change_event_id::text AS record_reference,
  c.source_version_reference::text AS record_version_reference,
  c.batch_id::text AS batch_id,
  c.source_system_id::text AS source_system_id,
  'operation_type'::text AS attribute_name,
  'M6_CDC_INVALID_OPERATION'::text AS rule_name,
  'LOAD_VALIDATION'::text AS issue_type,
  ('Expected I, U or D; received ' || quote_literal(c.operation_type))::text
    AS issue_description,
  'BLOCKING'::text AS severity
FROM bronze.cdc_change_event c
WHERE c.operation_type NOT IN ('I', 'U', 'D')

UNION ALL
SELECT 'BRONZE', 'CDC_CHANGE_EVENT', c.change_event_id::text,
       c.source_version_reference::text, c.batch_id::text,
       c.source_system_id::text, 'source_system_id',
       'M6_CDC_BATCH_SOURCE_MISMATCH', 'SOURCE_CONSISTENCY',
       CASE WHEN b.batch_id IS NULL
         THEN 'CDC event references a batch absent from Bronze'
         ELSE 'CDC source differs from the batch source'
       END,
       'BLOCKING'
FROM bronze.cdc_change_event c
LEFT JOIN bronze.ingestion_batch b ON b.batch_id = c.batch_id
WHERE b.batch_id IS NULL
   OR c.source_system_id IS DISTINCT FROM b.source_system_id

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'source_customer_reference',
       'M6_CUSTOMER_REFERENCE_BLANK', 'MISSING_VALUE',
       'Source customer reference is blank or whitespace', 'BLOCKING'
FROM raw_customers r
WHERE btrim(r.source_customer_reference) = ''

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'source_system_id',
       'M6_RAW_SOURCE_IN_WRONG_TABLE', 'SOURCE_CONSISTENCY',
       'Expected ' || r.expected_source || ' in this source-specific raw table',
       'BLOCKING'
FROM raw_customers r
WHERE r.source_system_id <> r.expected_source

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'batch_id',
       'M6_RAW_BATCH_SOURCE_MISMATCH', 'SOURCE_CONSISTENCY',
       CASE WHEN b.batch_id IS NULL
         THEN 'Raw customer record references a batch absent from Bronze'
         ELSE 'Raw customer source differs from the batch source'
       END,
       'BLOCKING'
FROM raw_customers r
LEFT JOIN bronze.ingestion_batch b ON b.batch_id = r.batch_id
WHERE b.batch_id IS NULL
   OR r.source_system_id IS DISTINCT FROM b.source_system_id

UNION ALL
SELECT 'BRONZE', 'RAW_KYC_VERIFICATION', k.bronze_record_reference::text,
       k.source_kyc_reference::text, k.batch_id::text,
       k.source_system_id::text, 'verification_status',
       'M6_KYC_MISSING_DOCUMENT', 'KYC_GAP',
       'Source KYC verification is missing a required document; Member 5 must link a verification case',
       'REPORTABLE'
FROM bronze.raw_kyc_verification k
WHERE k.verification_status = 'MISSING_DOCUMENT'

UNION ALL
SELECT 'BRONZE', 'RAW_KYC_VERIFICATION', k.bronze_record_reference::text,
       k.source_kyc_reference::text, k.batch_id::text,
       k.source_system_id::text, 'verification_status',
       'M6_KYC_EXPIRED_STATUS', 'KYC_GAP',
       'Source KYC verification is marked expired; Member 5 must link a verification case',
       'REPORTABLE'
FROM bronze.raw_kyc_verification k
WHERE k.verification_status = 'EXPIRED'

UNION ALL
SELECT 'SILVER', 'SOURCE_CUSTOMER_RECORD', s.source_customer_record_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'is_current_version',
       'M6_DUPLICATE_CURRENT_SOURCE_VERSION', 'DUPLICATE_CURRENT',
       'More than one current version exists for the same source identity',
       'BLOCKING'
FROM silver.source_customer_record s
WHERE s.is_current_version
  AND EXISTS (
    SELECT 1 FROM silver.source_customer_record x
    WHERE x.source_system_id = s.source_system_id
      AND x.source_customer_reference = s.source_customer_reference
      AND x.is_current_version
      AND x.source_customer_record_id <> s.source_customer_record_id
  )

UNION ALL
SELECT 'SILVER', 'CUSTOMER_SOURCE_MATCH', m.match_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'customer_id',
       'M6_ACCEPTED_MATCH_NO_CUSTOMER', 'IDENTITY_INTEGRITY',
       'An ACCEPTED match has no confirmed customer ID', 'BLOCKING'
FROM silver.customer_source_match m
JOIN silver.source_customer_record s
  ON s.source_customer_record_id = m.source_customer_record_id
WHERE m.match_status = 'ACCEPTED' AND m.customer_id IS NULL

UNION ALL
SELECT 'SILVER', 'CUSTOMER_SOURCE_MATCH', m.match_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'is_current_match',
       'M6_DUPLICATE_CURRENT_ACCEPTED_MATCH', 'IDENTITY_INTEGRITY',
       'A source identity has more than one current ACCEPTED match',
       'BLOCKING'
FROM silver.customer_source_match m
JOIN silver.source_customer_record s
  ON s.source_customer_record_id = m.source_customer_record_id
WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
  AND EXISTS (
    SELECT 1
    FROM silver.customer_source_match m2
    JOIN silver.source_customer_record s2
      ON s2.source_customer_record_id = m2.source_customer_record_id
    WHERE s2.source_system_id = s.source_system_id
      AND s2.source_customer_reference = s.source_customer_reference
      AND m2.is_current_match AND m2.match_status = 'ACCEPTED'
      AND m2.match_id <> m.match_id
  )

UNION ALL
SELECT 'SILVER', 'CUSTOMER_ATTRIBUTE_SOURCE', a.attribute_source_id::text,
       a.effective_from::text, NULL::text, NULL::text, 'is_current',
       'M6_DUPLICATE_CURRENT_ATTRIBUTE_SOURCE', 'DUPLICATE_CURRENT',
       'A customer attribute has more than one current selected source',
       'BLOCKING'
FROM silver.customer_attribute_source a
WHERE a.is_current
  AND EXISTS (
    SELECT 1 FROM silver.customer_attribute_source a2
    WHERE a2.customer_id = a.customer_id
      AND a2.attribute_name = a.attribute_name
      AND a2.is_current
      AND a2.attribute_source_id <> a.attribute_source_id
  )

UNION ALL
SELECT 'GOLD', 'DIM_CUSTOMER', d.customer_key::text,
       d.effective_from::text, NULL::text, NULL::text, 'current_flag',
       'M6_DUPLICATE_CURRENT_CUSTOMER_DIM', 'DUPLICATE_CURRENT',
       'A customer has more than one current dimension row', 'BLOCKING'
FROM gold.dim_customer d
WHERE d.current_flag
  AND EXISTS (
    SELECT 1 FROM gold.dim_customer d2
    WHERE d2.customer_id = d.customer_id AND d2.current_flag
      AND d2.customer_key <> d.customer_key
  )

UNION ALL
SELECT 'GOLD', 'FACT_CUSTOMER_SNAPSHOT', f.customer_snapshot_id::text,
       f.snapshot_date::text, NULL::text, NULL::text, 'customer_key',
       'M6_FACT_DIM_CUSTOMER_MISMATCH', 'REPORTING_INTEGRITY',
       'Snapshot customer ID differs from its customer dimension ID',
       'BLOCKING'
FROM gold.fact_customer_snapshot f
JOIN gold.dim_customer d ON d.customer_key = f.customer_key
WHERE f.customer_id <> d.customer_id

UNION ALL
SELECT 'GOLD', 'FACT_COMPLIANCE_EXCEPTION', e.exception_fact_id::text,
       e.as_of_date::text, NULL::text, NULL::text,
       'verification_case_id/aml_case_id',
       'M6_EXCEPTION_CASE_LINK_INVALID', 'REPORTING_INTEGRITY',
       'Exactly one verification or AML case must be linked', 'BLOCKING'
FROM gold.fact_compliance_exception e
WHERE (e.verification_case_id IS NULL) = (e.aml_case_id IS NULL);

COMMENT ON VIEW silver.vw_member6_quality_findings IS
  'Member 6 read-only structural and KYC-gap findings. Member 1 owns CDC load failures; Member 5 owns reportable KYC/AML cases.';

-- Expected after Member 1 demo: CDC-019 appears as M6_CDC_INVALID_OPERATION.
SELECT rule_name, data_layer, entity_name, record_reference, severity
FROM silver.vw_member6_quality_findings
ORDER BY rule_name, record_reference;

-- <<< END SOURCE FILE: sql/module6_sunny/01_quality_findings.sql

-- >>> BEGIN SOURCE FILE: sql/module6_sunny/02_record_quality_issues.sql

-- Member 6: persist newly detected structural failures in the shared issue table.
-- Run after 01_quality_findings.sql. One run ID gives idempotent reruns.

CREATE OR REPLACE FUNCTION silver.member6_sync_quality_issues(
  p_validation_run_id text
)
RETURNS integer
LANGUAGE plpgsql
AS $member6_sync$
DECLARE
  v_inserted integer;
BEGIN
  IF p_validation_run_id IS NULL
     OR btrim(p_validation_run_id) = ''
     OR length(p_validation_run_id) > 100 THEN
    RAISE EXCEPTION 'Provide a nonblank validation run ID of at most 100 characters';
  END IF;

  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, batch_id, source_system_id,
    verification_case_id, validation_run_id, data_layer, entity_name,
    record_reference, record_version_reference, attribute_name,
    rule_name, rule_version, issue_type, issue_description,
    severity, detected_at, resolved_at, issue_status
  )
  SELECT
    'M6-' || substr(md5(concat_ws('|',
      p_validation_run_id, f.rule_name, f.entity_name,
      f.record_reference, f.record_version_reference
    )), 1, 32),
    CASE WHEN EXISTS (
      SELECT 1 FROM silver.ingestion_batch b WHERE b.batch_id = f.batch_id
    ) THEN f.batch_id ELSE NULL END,
    CASE WHEN EXISTS (
      SELECT 1 FROM silver.source_system s
      WHERE s.source_system_id = f.source_system_id
    ) THEN f.source_system_id ELSE NULL END,
    NULL,
    p_validation_run_id,
    f.data_layer,
    f.entity_name,
    f.record_reference,
    f.record_version_reference,
    f.attribute_name,
    f.rule_name,
    '1.0',
    f.issue_type,
    left(f.issue_description, 1000),
    f.severity,
    clock_timestamp(),
    NULL,
    'OPEN'
  FROM silver.vw_member6_quality_findings f
  WHERE f.rule_name NOT IN (
    -- Member 1 already records load-validation failures by batch.
    'M6_CDC_INVALID_OPERATION',
    'M6_CDC_BATCH_SOURCE_MISMATCH',
    -- Reportable KYC gaps require Member 5's verification-case FK first.
    'M6_KYC_MISSING_DOCUMENT',
    'M6_KYC_EXPIRED_STATUS'
  )
  ON CONFLICT (data_quality_issue_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$member6_sync$;

COMMENT ON FUNCTION silver.member6_sync_quality_issues(text) IS
  'Stores non-CDC structural findings once per validation run; does not alter source or Bronze rows. Recheck before manually resolving an issue.';

-- Example after all relevant tables contain data:
-- SELECT silver.member6_sync_quality_issues('M6-2026-10-12-01');
-- SELECT * FROM silver.data_quality_issue
-- WHERE validation_run_id = 'M6-2026-10-12-01';

-- <<< END SOURCE FILE: sql/module6_sunny/02_record_quality_issues.sql

-- >>> BEGIN SOURCE FILE: sql/module6_sunny/04_audit_quality_changes.sql

-- Member 6: demonstrate automatic auditing of issue INSERT/UPDATE/DELETE.
-- Run after shared tables exist. The trigger records successful, committed
-- row changes; it does not record SELECT, failed statements or rollbacks.

CREATE OR REPLACE FUNCTION silver.member6_audit_quality_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, silver
AS $member6_audit$
DECLARE
  v_record_reference text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_record_reference := OLD.data_quality_issue_id;
  ELSE
    v_record_reference := NEW.data_quality_issue_id;
  END IF;

  INSERT INTO silver.access_audit_log (
    audit_id, user_id, role_id, actor_identifier, query_reference,
    action_type, resource_name, record_reference,
    event_timestamp, success_flag, ip_address
  )
  VALUES (
    'M6A-' || substr(md5(
      clock_timestamp()::text || random()::text || v_record_reference
    ), 1, 32),
    NULL, NULL, session_user::text,
    NULLIF(current_setting('application_name', true), ''),
    TG_OP, TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
    v_record_reference, clock_timestamp(), TRUE,
    inet_client_addr()::text
  );

  RETURN NULL; -- return value ignored by an AFTER trigger
END;
$member6_audit$;

REVOKE ALL ON FUNCTION silver.member6_audit_quality_write() FROM PUBLIC;

DO $member6_attach_audit$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'silver.data_quality_issue'::regclass
      AND tgname = 'tr_member6_quality_issue_audit'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER tr_member6_quality_issue_audit
    AFTER INSERT OR UPDATE OR DELETE ON silver.data_quality_issue
    FOR EACH ROW EXECUTE FUNCTION silver.member6_audit_quality_write();
  END IF;
END;
$member6_attach_audit$;

CREATE OR REPLACE FUNCTION silver.member6_prevent_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $member6_append_only$
BEGIN
  RAISE EXCEPTION 'silver.access_audit_log is append-only';
END;
$member6_append_only$;

REVOKE ALL ON FUNCTION silver.member6_prevent_audit_mutation() FROM PUBLIC;

DO $member6_attach_protection$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'silver.access_audit_log'::regclass
      AND tgname = 'tr_member6_audit_append_only'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER tr_member6_audit_append_only
    BEFORE UPDATE OR DELETE ON silver.access_audit_log
    FOR EACH ROW EXECUTE FUNCTION silver.member6_prevent_audit_mutation();
  END IF;
END;
$member6_attach_protection$;

COMMENT ON FUNCTION silver.member6_audit_quality_write() IS
  'Audit committed quality-issue row changes using the database login as actor. Does not provide SELECT auditing.';

-- <<< END SOURCE FILE: sql/module6_sunny/04_audit_quality_changes.sql
