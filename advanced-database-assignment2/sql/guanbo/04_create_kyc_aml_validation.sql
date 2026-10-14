-- PostgreSQL 15+
-- Member 5：KYC/AML 校验规则，以及把发现登记为数据质量问题。
--
-- 结构：标识生成 / 身份解析 / KYC 规则 8 条 / AML 规则 10 条 / 规则到案件类型映射 / 问题登记。
-- 设计：每条记录只保留最严重的一条发现（两个函数共用末尾同一套排序）；规则不负责建案件，
--       建案在 05_create_case_processing.sql；批次参数传 NULL 表示检查全部批次并取最新版本。

-- 用"来源系统 + 来源编号"算出主键。固定算法带来两个好处：
--   1. 重复处理同一批数据得到同一个编号，天然幂等，不会重复插入；
--   2. 别处只拿到业务编号也能定位到已发布事件，不必回查数据库。
CREATE OR REPLACE FUNCTION silver.kyc_verification_id(
  p_source_system_id varchar,
  p_source_kyc_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $kyc_id$
  SELECT 'KYC-' || upper(substr(md5(p_source_system_id || ':' || p_source_kyc_reference), 1, 16));
$kyc_id$;

CREATE OR REPLACE FUNCTION silver.aml_screening_id(
  p_source_system_id varchar,
  p_source_screening_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $aml_id$
  SELECT 'AML-' || upper(substr(md5(p_source_system_id || ':' || p_source_screening_reference), 1, 16));
$aml_id$;

COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  '由"来源系统 + 来源 KYC 编号"生成稳定的验证事件主键，保证重复处理不会产生重复行。';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  '由"来源系统 + 来源筛查编号"生成稳定的筛查事件主键，作用同 KYC 版本。';

-- 第 2 节  身份解析（两个检测函数共用）

-- 一条事件要能回答"当事人是谁"。本函数返回两个编号：
--   source_customer_record_id：来源系统里那条客户记录，在 Silver 中对应哪条记录
--   customer_id              ：如果已成功合并，对应的金客户编号
-- 任何一个查不到就返回 NULL，调用方据此判断"身份尚未合并"。
CREATE OR REPLACE FUNCTION silver.resolve_event_identity(
  p_entity varchar,
  p_source_system_id varchar,
  p_source_reference varchar,
  p_batch_id varchar
)
RETURNS TABLE (
  source_customer_record_id varchar,
  customer_id varchar
)
LANGUAGE plpgsql
STABLE
AS $resolve_identity$
DECLARE
  v_customer_reference varchar(100);
BEGIN
  -- 先从对应事件表里取出这条事件引用的"来源客户编号"
  IF p_entity = 'KYC' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_kyc_verification raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_kyc_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSIF p_entity = 'AML' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_aml_screening raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_screening_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSE
    RAISE EXCEPTION '不支持的类型 %，应为 KYC 或 AML', p_entity;
  END IF;

  SELECT min(source_record.source_customer_record_id)
  INTO source_customer_record_id
  FROM silver.source_customer_record source_record
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference
    AND source_record.is_current_version;

  -- 只有状态 ACCEPTED 且当前有效的匹配才算"身份已确认"
  SELECT min(current_match.customer_id)
  INTO customer_id
  FROM silver.source_customer_record source_record
  JOIN silver.customer_source_match current_match
    ON current_match.source_customer_record_id = source_record.source_customer_record_id
   AND current_match.is_current_match
   AND current_match.match_status = 'ACCEPTED'
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference;

  RETURN NEXT;
END;
$resolve_identity$;

COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  '解析一条事件对应的来源客户记录与金客户编号；查不到返回 NULL，表示身份尚未合并。';

-- 第 3 节  KYC 验证规则（8 条）

DROP FUNCTION IF EXISTS silver.detect_kyc_verification_issues(varchar, date);

CREATE OR REPLACE FUNCTION silver.detect_kyc_verification_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_kyc$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  -- 每个来源编号只取最新一版 Bronze 行；批次传 NULL 时即"全批次取最新"
  staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_kyc_reference))
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_kyc_reference) AS source_kyc_reference,
      btrim(raw.source_customer_reference) AS source_customer_reference,
      raw.verification_type,
      raw.verification_status,
      raw.verification_date,
      raw.expiry_date
    FROM bronze.raw_kyc_verification raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_kyc_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  -- 补上身份信息，并算出"类型/状态是否可识别"
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      reference_date.as_of_date,
      staged.verification_type IN (
        'IDENTITY_DOCUMENT', 'ADDRESS_VERIFICATION', 'SOURCE_OF_FUNDS',
        'ENHANCED_DUE_DILIGENCE', 'PERIODIC_REVIEW'
      ) AS type_is_known,
      staged.verification_status IN (
        'VERIFIED', 'PENDING', 'MISSING_DOCUMENT', 'FAILED', 'EXPIRED'
      ) AS status_is_known
    FROM staged
    CROSS JOIN reference_date
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'KYC', staged.source_system_id, staged.source_kyc_reference, p_batch_id
    ) identity
  ),
  -- 把 8 条规则的判断条件在这里算出来，下面按规则逐条列发现
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- 有效期已过（验证时间本身晚于基准日的不算过期）
      (
        evaluated.expiry_date IS NOT NULL
        AND evaluated.verification_date::date < evaluated.as_of_date
        AND evaluated.expiry_date < evaluated.as_of_date
        AND evaluated.verification_status NOT IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED')
      ) AS is_expired,
      -- 状态写着"已验证"，但按记录的有效期已不能依赖
      (
        evaluated.verification_status = 'VERIFIED'
        AND (
          evaluated.expiry_date IS NULL
          OR evaluated.expiry_date < evaluated.verification_date::date
          OR evaluated.expiry_date < evaluated.as_of_date
        )
      ) AS is_discrepancy,
      -- 验证没有完成，构成资料缺口
      evaluated.verification_status IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED') AS is_gap
    FROM evaluated
  ),
  -- 每个规则块只写本规则特有的内容：e.* 展开 evaluated_rules 的公共列（来源编号、身份等），
  -- 其后是规则名、问题类型、严重程度，末项为去重用的规则优先级。
  -- 8 条规则各自的命中结果，统一成一张发现清单
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'KYC_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'KYC_SUBJECT_MISSING' AS issue_type,
      '这条验证事件既没有金客户也没有来源客户记录，缺少主体引用。' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'KYC_IDENTITY_LINK_MISMATCH', 'KYC_IDENTITY_MISMATCH',
      '这条事件关联的金客户与来源客户记录，并不是同一个已确认的身份。',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'verification_type', 'KYC_VERIFICATION_TYPE_INVALID', 'KYC_VERIFICATION_TYPE_INVALID',
      concat('验证类型 ', COALESCE(e.verification_type, 'NULL'), ' 不是可识别的 KYC 验证类型。'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_INVALID', 'KYC_VERIFICATION_STATUS_INVALID',
      concat('验证状态 ', COALESCE(e.verification_status, 'NULL'), ' 不是可识别的 KYC 验证状态。'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.status_is_known

    UNION ALL
    SELECT
      e.*,
      'expiry_date', 'KYC_VERIFICATION_EXPIRED', 'KYC_VERIFICATION_EXPIRED',
      concat(
        '到基准日已失效：状态 ', e.verification_status,
        '，有效期 ', COALESCE(e.expiry_date::text, 'NULL'), '。'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_expired

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_DISCREPANCY', 'KYC_VERIFICATION_STATUS_DISCREPANCY',
      concat(
        '状态为已验证，但按记录的有效期已不能依赖：有效期 ',
        COALESCE(e.expiry_date::text, '空'),
        '，验证时间 ', e.verification_date::date::text, '。'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_discrepancy

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_INCOMPLETE', 'KYC_VERIFICATION_GAP',
      concat('验证没有完成：状态 ', e.verification_status, '。'),
      'MEDIUM', 'KYC_GAP', 3
    FROM evaluated_rules e
    WHERE e.is_gap

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'KYC_VERIFICATION_UNRESOLVED_IDENTITY', 'KYC_IDENTITY_UNRESOLVED',
      '这条验证事件挂在来源客户记录上，但金客户尚未确认；报表仍应包含它。',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  -- 每条记录只留最严重的一条（两个检测函数使用同一套排序口径）
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_kyc_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_kyc$;

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  '对一个批次的 KYC 验证事件套用 8 条规则，每条记录只返回最严重的一条发现。批次传 NULL 表示检查全部批次并取最新版本。';

-- 第 4 节  AML 筛查规则（10 条）

DROP FUNCTION IF EXISTS silver.detect_aml_screening_issues(varchar, date);

CREATE OR REPLACE FUNCTION silver.detect_aml_screening_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_aml$
  WITH staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_screening_reference))
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_screening_reference) AS source_screening_reference,
      btrim(raw.source_customer_reference) AS source_customer_reference,
      raw.screening_type,
      raw.screening_date,
      raw.screening_result,
      raw.match_score,
      COALESCE(raw.review_required_flag, false) AS review_required_flag
    FROM bronze.raw_aml_screening raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_screening_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      staged.screening_type IN ('SANCTIONS', 'PEP', 'WATCHLIST', 'ADVERSE_MEDIA') AS type_is_known,
      staged.screening_result IN (
        'CLEAR', 'POTENTIAL_MATCH', 'CONFIRMED_MATCH', 'FALSE_POSITIVE'
      ) AS result_is_known,
      staged.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH') AS result_is_alert
    FROM staged
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'AML', staged.source_system_id, staged.source_screening_reference, p_batch_id
    ) identity
  ),
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- 未命中却要求复核，且分数未达警报级 → 状态矛盾
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.review_required_flag
        AND COALESCE(evaluated.match_score, 0) < 0.7500
      ) AS is_clear_with_review,
      -- 未命中却带着警报级分数 → 状态矛盾
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.match_score IS NOT NULL
        AND evaluated.match_score >= 0.7500
      ) AS is_clear_with_alert_score,
      -- 警报却没标"需要复核" → 状态矛盾
      (
        evaluated.result_is_alert
        AND NOT evaluated.review_required_flag
      ) AS is_review_flag_missing
    FROM evaluated
  ),
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'AML_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'AML_SUBJECT_MISSING' AS issue_type,
      '这条筛查事件既没有金客户也没有来源客户记录，缺少主体引用。' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'AML_IDENTITY_LINK_MISMATCH', 'AML_IDENTITY_MISMATCH',
      '这条筛查事件关联的金客户与来源客户记录，并不是同一个已确认的身份。',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'screening_type', 'AML_SCREENING_TYPE_INVALID', 'AML_SCREENING_TYPE_INVALID',
      concat('名单类别 ', COALESCE(e.screening_type, 'NULL'), ' 不是可识别的筛查类型。'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_SCREENING_RESULT_INVALID', 'AML_SCREENING_RESULT_INVALID',
      concat('筛查结论 ', COALESCE(e.screening_result, 'NULL'), ' 不是可识别的筛查结论。'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.result_is_known

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_REVIEW_FLAG_INCONSISTENT', 'AML_REVIEW_FLAG_MISSING',
      concat(
        '筛查结论 ', e.screening_result,
        ' 属于警报，但 review_required_flag 为假；疑似命中必须复核。'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_review_flag_missing

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_REVIEW_REQUIRED', 'AML_SCREENING_ALERT',
      concat(
        '筛查结论为 ', e.screening_result,
        '，相似度 ', COALESCE(e.match_score::text, 'NULL'),
        '；这是需要调查的警报，本身不等于已确认的问题。'
      ),
      'MEDIUM', NULL::varchar, 2
    FROM evaluated_rules e
    WHERE e.result_is_alert

    UNION ALL
    SELECT
      e.*,
      'review_required_flag', 'AML_CLEAR_SCREENING_WITH_REVIEW', 'AML_STATUS_DISCREPANCY',
      concat(
        '结论为未命中却要求复核，且相似度未达警报级：',
        COALESCE(e.match_score::text, 'NULL'), '。'
      ),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_review

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT', 'AML_STATUS_DISCREPANCY',
      concat('结论为未命中，却带着警报级相似度 ', e.match_score::text, '。'),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_alert_score

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_OUT_OF_RANGE', 'AML_MATCH_SCORE_INVALID',
      concat('相似度 ', e.match_score::text, ' 超出有效范围 0.0000 到 1.0000。'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.match_score IS NOT NULL
      AND (e.match_score < 0 OR e.match_score > 1)

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_MISSING', 'AML_MATCH_SCORE_MISSING',
      '返回了警报却没有相似度分数，无法判断命中强度。',
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.result_is_alert
      AND e.match_score IS NULL

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'AML_SCREENING_UNRESOLVED_IDENTITY', 'AML_IDENTITY_UNRESOLVED',
      '这条筛查事件挂在来源客户记录上，但金客户尚未确认；报表仍应包含它。',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_screening_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_aml$;

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  '对一个批次的 AML 筛查事件套用 10 条规则，每条记录只返回最严重的一条发现。批次传 NULL 表示检查全部批次并取最新版本。';

-- 第 5 节  规则 → 案件类型映射（报告口径的单一来源）

CREATE SEQUENCE IF NOT EXISTS silver.compliance_case_seed;

-- 报告要求：可报告的 KYC 缺口、身份不匹配、状态矛盾，必须建立
-- KYC_GAP / IDENTITY_MISMATCH / STATUS_DISCREPANCY 三种案件之一。
-- 这个函数就是这条要求的落地处——改口径只改这一处，不用动规则逻辑。
-- 返回 NULL 表示该规则只登记质量问题、不建案件（例如 LOW 级的"身份尚未合并"）。
CREATE OR REPLACE FUNCTION silver.compliance_rule_case_type(
  p_rule_name varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $rule_case_type$
  SELECT CASE p_rule_name
    WHEN 'KYC_VERIFICATION_INCOMPLETE' THEN 'KYC_GAP'
    WHEN 'KYC_VERIFICATION_EXPIRED' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_VERIFICATION_STATUS_DISCREPANCY' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_REVIEW_REQUIRED' THEN 'AML_SCREENING_REVIEW'
    WHEN 'AML_REVIEW_FLAG_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_WITH_REVIEW' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    ELSE NULL
  END;
$rule_case_type$;

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  '规则到案件类型的唯一映射。返回 NULL 表示该规则只登记质量问题、不建案件。';

-- 第 6 节  问题登记

-- 把一条发现登记成 Silver 的数据质量问题。
--
-- 问题编号由"批次 + 规则 + 记录"算出，所以重跑同一批次只会**更新**同一条问题，
-- 不会追加重复行。问题先置为 OPEN；等规则不再报它时，由
-- 05_create_case_processing.sql 置为 RESOLVED。
-- 返回该规则对应的案件类型，供建案步骤使用。
CREATE OR REPLACE FUNCTION silver.register_compliance_finding(
  p_batch_id varchar,
  p_source_system_id varchar,
  p_entity_name varchar,
  p_record_reference varchar,
  p_record_version_reference varchar,
  p_attribute_name varchar,
  p_rule_name varchar,
  p_issue_type varchar,
  p_issue_description text,
  p_severity varchar,
  p_rule_case_type varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $register_finding$
DECLARE
  v_issue_id varchar(50);
  v_case_type varchar(50);
BEGIN
  v_issue_id := 'DQ-KYCAML-' || upper(
    substr(
      md5(concat_ws(':', p_batch_id, p_rule_name, p_entity_name, p_record_reference)),
      1,
      16
    )
  );

  v_case_type := silver.compliance_rule_case_type(p_rule_name);

  -- 案件本身由 05_create_case_processing.sql 建立，所以这里不写案件号，
  -- 避免本文件依赖下一个文件。
  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, batch_id, source_system_id, verification_case_id,
    validation_run_id, data_layer, entity_name, record_reference,
    record_version_reference, attribute_name, rule_name, rule_version,
    issue_type, issue_description, severity, detected_at, resolved_at, issue_status
  )
  VALUES (
    v_issue_id, p_batch_id, p_source_system_id, NULL,
    'KYC-AML-M5-' || p_batch_id, 'SILVER', p_entity_name, p_record_reference,
    p_record_version_reference, p_attribute_name, p_rule_name, '1.0',
    p_issue_type, left(p_issue_description, 1000), p_severity,
    clock_timestamp(), NULL, 'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    attribute_name = EXCLUDED.attribute_name,
    issue_type = EXCLUDED.issue_type,
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    issue_status = 'OPEN';

  RETURN v_case_type;
END;
$register_finding$;

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  '把一条校验发现登记为数据质量问题，并返回该规则对应的案件类型。';

-- 本模块按 (校验批次, 规则, 记录) 定位并关闭问题，因此为该访问路径建索引。
CREATE INDEX IF NOT EXISTS ix_data_quality_issue_run_record
  ON silver.data_quality_issue (validation_run_id, rule_name, record_reference);
