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
