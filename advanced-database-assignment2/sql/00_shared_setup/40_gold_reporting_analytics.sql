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
