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
