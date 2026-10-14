-- PostgreSQL 15+
-- Member 5：把 Bronze 里的 KYC 验证 / AML 筛查原始数据，校验后发布到 Silver。
--
-- 【为什么是"事件驱动"而不是"批次状态驱动"】
--   只要 Bronze 里有这个批次的原始数据就发布。这一点很关键：B2-AMLKYC 因为源数据里
--   有个 CDC 事件的 operation_type 是空的，被 Member 1 故意置为 FAILED，但它的原始行

-- 第 1 节  共用步骤

-- 把指定批次的 Bronze 原始行登记到临时表，并补上"身份查找"结果。
--
-- 身份查找要回答两个问题：
--   source_customer_record_id：来源系统里的这条客户记录，在 Silver 里对应哪条记录
--   customer_id              ：如果它已经成功合并，对应的金客户是谁
-- 找不到就分别是 NULL，事件仍然会发布（后续会报"身份未合并"的提示或异常）。
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

-- 把已经发布到 Silver 的事件记入数据血缘表，形成"Bronze 原始行 → Silver 事件"的链路。
-- 同一行重复发布时不会产生重复血缘（lineage_id 是算出来的固定值）。
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

-- 第 2 节  事件发布（每种事件一个过程，字段逐条对应，便于核对）

-- 发布 KYC 验证事件：先登记并查身份，再检测问题，最后只发布非阻断的那些。
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
    RAISE NOTICE '批次 % 在 Bronze 里没有 KYC 验证行，无需发布', p_batch_id;
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
  -- 阻断级问题的记录不发布
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

  RAISE NOTICE '批次 %：KYC 登记 % 行，发布 % 行，阻断 % 条',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_kyc$;

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  '把一批 Bronze KYC 验证行校验后发布到 Silver；存在阻断级问题的行不予发布。';

-- 发布 AML 筛查事件：步骤与 KYC 版完全一致，只是表不同。
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
    RAISE NOTICE '批次 % 在 Bronze 里没有 AML 筛查行，无需发布', p_batch_id;
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

  RAISE NOTICE '批次 %：AML 登记 % 行，发布 % 行，阻断 % 条',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_aml$;

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  '把一批 Bronze AML 筛查行校验后发布到 Silver；存在阻断级问题的行不予发布。';

-- 第 3 节  批次总入口

-- 一个批次走完全流程：建身份 → 发布两类事件 → 跑规则并登记问题。
--
-- 检测结果先落临时表，后面统计条数和登记问题都复用它，避免重复计算。
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
    RAISE EXCEPTION '必须提供报告基准日，用于判断 KYC 验证是否过期';
  END IF;

  SELECT min(source_system_id)
  INTO v_source_system_id
  FROM (
    SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_sources;

  IF v_source_system_id IS NULL THEN
    RAISE EXCEPTION '批次 % 在 Bronze 里没有 KYC 或 AML 行', p_batch_id;
  END IF;

  -- 身份登记要扫全部客户引用，开销较大，所以每个会话只做一次，不是每批都做。
  CREATE TEMP TABLE IF NOT EXISTS tmp_identity_loaded (
    loaded_at timestamp NOT NULL
  ) ON COMMIT PRESERVE ROWS;

  IF NOT EXISTS (SELECT 1 FROM tmp_identity_loaded) THEN
    CALL silver.load_kyc_aml_customer_identity();
    INSERT INTO tmp_identity_loaded (loaded_at) VALUES (clock_timestamp());
  END IF;

  CALL silver.publish_kyc_verification_batch(p_batch_id, p_reference_date);
  CALL silver.publish_aml_screening_batch(p_batch_id, p_reference_date);

  -- 规则检测结果落表，供统计与登记共用
  DROP TABLE IF EXISTS tmp_kyc_findings;
  CREATE TEMP TABLE tmp_kyc_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  DROP TABLE IF EXISTS tmp_aml_findings;
  CREATE TEMP TABLE tmp_aml_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_kyc_count FROM tmp_kyc_findings;
  SELECT count(*)::integer INTO v_aml_count FROM tmp_aml_findings;

  -- 登记为数据质量问题（案件由 05_create_case_processing.sql 统一建立）
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

  RAISE NOTICE '批次 % 处理完成（基准日 %）：KYC 发现 % 条，AML 发现 % 条',
    p_batch_id, p_reference_date, v_kyc_count, v_aml_count;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Member 5 批次总入口：建立客户身份 → 发布 KYC 与 AML 事件到 Silver → 跑校验规则并登记问题。';
