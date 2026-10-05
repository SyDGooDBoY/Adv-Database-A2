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
