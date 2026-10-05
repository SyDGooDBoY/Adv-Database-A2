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
