-- PostgreSQL 15+
-- Member 5：KYC/AML 模块在 Bronze 层的输入数据。
--
-- 【为什么要在这里塞种子数据】
--   数据来自仓库里的合成 CSV。为了让模块在 CloudBeaver 里能直接跑起来，不依赖
--   "PostgreSQL 服务器能读到本地 Windows 路径"，所以把 CSV 内容写成 INSERT。
--
-- 【两条重要约束】
--   1. Bronze 只增不删、归 Member 1 所有，所以每次插入前先判断"这个批次在不在"，
--      在就跳过。重复执行不会产生重复行，也不会覆盖已有原始数据。
--   2. 批次控制信息要同时写进 source_systems（模拟业务库）和 silver（控制层），
--      两处字段相同、数据同源，所以用一段循环把同一份数据喂给两边。
--
-- 【数据构成】
--   B1-AMLKYC：9 条 KYC 验证 + 9 条 AML 筛查 + 9 条客户资料
--   B2-AMLKYC：1 条 AML 筛查（监控名单疑似命中，演示里的 AML 异常就来自它）
--
-- 【关于 B2-AMLKYC】
--   Member 1 会把 B2-AMLKYC 故意置为 FAILED（源数据里有个 CDC 事件的
--   operation_type 是空的），但它的原始行仍在 Bronze 里，本模块照样处理，
--   这样那条合规异常才不会丢。

-- 批次控制信息：一处定义，两处使用
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
    -- 模拟业务库
    INSERT INTO source_systems.ingestion_batch (
      batch_id, source_system_id, load_type, started_at, completed_at,
      load_status, records_received, records_processed, watermark_start, watermark_end
    )
    VALUES (
      v_batch[1], 'AMLKYC', v_batch[2], v_batch[3]::timestamp, v_batch[4]::timestamp,
      'SUCCEEDED', v_batch[5]::integer, v_batch[6]::integer, v_batch[7], v_batch[8]
    )
    ON CONFLICT (batch_id) DO NOTHING;

    -- 集成控制层。已存在的批次保持原样，免得覆盖 Member 1 记录的失败状态。
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

-- 来源系统定义（Silver 的外键要求它先存在）
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

-- ============================================================================
-- KYC 验证原始数据：data/synthetic/raw_kyc_verification.csv（B1-AMLKYC，9 条）
-- ============================================================================
DO $seed_kyc_verification$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze 已有 B1-AMLKYC 的 KYC 行，跳过种子数据';
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

  RAISE NOTICE '已写入 9 条 Bronze KYC 验证行（B1-AMLKYC）';
END
$seed_kyc_verification$;

-- ============================================================================
-- AML 筛查原始数据：data/synthetic/raw_aml_screening.csv（B1 九条 + B2 一条）
-- ============================================================================
DO $seed_aml_screening$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze 已有 B1-AMLKYC 的 AML 行，跳过种子数据';
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

    RAISE NOTICE '已写入 9 条 Bronze AML 筛查行（B1-AMLKYC）';
  END IF;

  -- B2 那条：监控名单疑似命中，演示里的 AML 异常来源
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = 'B2-AMLKYC') THEN
    RAISE NOTICE 'Bronze 已有 B2-AMLKYC 的 AML 行，跳过种子数据';
  ELSE
    INSERT INTO bronze.raw_aml_screening (
      bronze_record_reference, source_system_id, batch_id, source_screening_reference,
      source_customer_reference, screening_type, screening_date, screening_result,
      match_score, provider_reference, review_required_flag, ingested_at
    )
    VALUES
      ('BR-SCR-010', 'AMLKYC', 'B2-AMLKYC', 'SCR-005-2', 'KYC-005', 'WATCHLIST', timestamp '2026-09-15 07:25:00', 'POTENTIAL_MATCH', 0.9200, 'SYN-HIT-005', true, timestamp '2026-09-15 08:24:00');

    RAISE NOTICE '已写入 1 条 Bronze AML 筛查行（B2-AMLKYC：监控名单疑似命中）';
  END IF;
END
$seed_aml_screening$;

-- ============================================================================
-- AML/KYC 客户资料：data/synthetic/raw_aml_kyc_customer.csv（9 条）
-- 这些属性用于给本模块的事件建立客户身份，让报表显示真实姓名而不是占位符。
-- 其中 KYC-nnn 与上面事件引用的来源客户编号一致。
-- ============================================================================
DO $seed_aml_kyc_customer$
BEGIN
  IF EXISTS (SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = 'B1-AMLKYC') THEN
    RAISE NOTICE 'Bronze 已有 AML/KYC 客户资料，跳过种子数据';
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

  RAISE NOTICE '已写入 9 条 Bronze AML/KYC 客户资料';
END
$seed_aml_kyc_customer$;
