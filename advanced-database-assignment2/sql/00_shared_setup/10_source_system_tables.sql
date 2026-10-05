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
