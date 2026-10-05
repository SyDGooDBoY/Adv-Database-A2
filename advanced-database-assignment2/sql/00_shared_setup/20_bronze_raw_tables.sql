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

