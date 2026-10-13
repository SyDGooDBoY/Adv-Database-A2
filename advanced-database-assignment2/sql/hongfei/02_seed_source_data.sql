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
