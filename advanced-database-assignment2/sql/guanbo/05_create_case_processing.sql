-- PostgreSQL 15+
-- Member 5: case-status processing for verification and AML investigations.
--
-- Two behaviours are required by the report:
--   1. A reportable KYC gap, identity mismatch or status discrepancy creates a
--      SPECIAL_VERIFICATION_CASE with case_type KYC_GAP, IDENTITY_MISMATCH or
--      STATUS_DISCREPANCY. A repeated finding for the same customer and issue
--      type reuses the existing open case instead of opening another.
--   2. Case status and its closing timestamp must agree, so a case is only
--      resolved when its finding is actually cleared.
--
-- The two case tables carry different keys, so the module opens them through two
-- functions. An AML screening alert is not a confirmed finding: its case is a
-- review of that alert, not confirmation that money laundering occurred.

-- Returns the SPECIAL_VERIFICATION_CASE representing a reportable KYC finding,
-- opening one when no case exists yet for that KYC event and case type.
-- 通用"查找或建立案件"步骤，两个专用函数共用。
--
-- 三段逻辑：按主体与案件类型找已有案件；找到就复用；找不到才生成编号并插入
-- （编号由"事件 + 案件类型"算出，同一问题重复检测会落到同一编号）。
-- 最后返回案件编号与触发类型，专用函数直接取用，不再各写一遍。
CREATE OR REPLACE FUNCTION silver.find_or_open_case(
  p_entity varchar,
  p_case_type varchar,
  p_record_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar,
  p_default_batch varchar DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $find_or_open$
DECLARE
  v_customer_id varchar(50);
  v_source_record_id varchar(50);
  v_screening_id varchar(50);
  v_customer_reference varchar(100);
  v_screening_type varchar(50);
  v_open_at timestamp;
  v_trigger_type varchar(50);
  v_table varchar;
  v_id_column varchar;
  v_prefix varchar;
  v_case_id varchar(50);
BEGIN
  -- 取出主体信息，并定下要写哪张案件表
  IF p_entity = 'KYC' THEN
    SELECT verification.customer_id, verification.source_customer_record_id
    INTO v_customer_id, v_source_record_id
    FROM silver.kyc_verification_record verification
    WHERE verification.kyc_verification_id = p_record_id;

    v_table := 'silver.special_verification_case';
    v_id_column := 'verification_case_id';
    v_prefix := 'SVCR-';

    v_trigger_type := CASE
      WHEN v_customer_id IS NOT NULL THEN 'GOLDEN_CUSTOMER'
      ELSE 'SOURCE_CUSTOMER_RECORD'
    END;
    -- 立案时间取触发事件的业务时间，重跑脚本不会让账龄凭空变大
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_KYC_VERIFICATION_EVENT'
    ), clock_timestamp());
  ELSIF p_entity = 'AML' THEN
    SELECT
      screening.customer_id,
      screening.source_customer_record_id,
      screening.source_screening_reference,
      screening.screening_type
    INTO v_customer_id, v_source_record_id, v_customer_reference, v_screening_type
    FROM silver.aml_screening_result screening
    WHERE screening.aml_screening_id = p_record_id;

    v_screening_id := p_record_id;
    v_table := 'silver.aml_case';
    v_id_column := 'aml_case_id';
    v_prefix := 'AMLC-';

    v_trigger_type := CASE v_screening_type
      WHEN 'SANCTIONS' THEN 'SANCTIONS_SCREENING'
      WHEN 'PEP' THEN 'PEP_SCREENING'
      WHEN 'WATCHLIST' THEN 'WATCHLIST_SCREENING'
      WHEN 'ADVERSE_MEDIA' THEN 'ADVERSE_MEDIA_SCREENING'
      ELSE 'SCREENING_ALERT'
    END;
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_AML_SCREENING_EVENT'
    ), clock_timestamp());
  ELSE
    RAISE EXCEPTION '不支持的类型 %，应为 KYC 或 AML', p_entity;
  END IF;

  -- 同一主体 + 同一案件类型只保留一个案件
  EXECUTE format(
    'SELECT %I FROM %s
     WHERE case_type = $1
       AND customer_id IS NOT DISTINCT FROM $2
       AND source_customer_record_id IS NOT DISTINCT FROM $3
     ORDER BY opened_at DESC, %I DESC
     LIMIT 1',
    v_id_column, v_table, v_id_column
  )
  INTO v_case_id
  USING p_case_type, v_customer_id, v_source_record_id;

  IF v_case_id IS NULL THEN
    v_case_id := v_prefix || upper(substr(md5(p_record_id || ':' || p_case_type), 1, 16));

    -- 案件严重程度用案件自己的量级，不出现 BLOCKING（那是数据问题的量级）
    IF p_entity = 'KYC' THEN
      INSERT INTO silver.special_verification_case (
        verification_case_id, customer_id, source_customer_record_id, match_id,
        kyc_verification_id, assigned_user_id, case_type, trigger_type,
        case_reason, case_status, severity, opened_at, resolved_at, resolution_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, NULL,
        p_record_id, NULL, p_case_type, v_trigger_type,
        left(concat(p_rule_name, ': ', p_issue_description), 1000),
        'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'CRITICAL'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (verification_case_id) DO NOTHING;
    ELSE
      -- AML 案件的风险等级上限是 HIGH，所以 BLOCKING 映射为 HIGH 而非 CRITICAL
      INSERT INTO silver.aml_case (
        aml_case_id, customer_id, source_customer_record_id, aml_screening_id,
        assigned_user_id, trigger_type, trigger_reference, case_type,
        case_status, risk_level, opened_at, closed_at, case_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, v_screening_id,
        NULL, v_trigger_type,
        left(concat(p_rule_name, ': ', v_customer_reference), 150),
        p_case_type, 'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'HIGH'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (aml_case_id) DO NOTHING;
    END IF;

    RAISE NOTICE '新开案件 %（% / %）', v_case_id, p_case_type, p_record_id;
  ELSE
    RAISE NOTICE '复用已有案件 %（% / %）', v_case_id, p_case_type, p_record_id;
  END IF;

  RETURN jsonb_build_object('case_id', v_case_id, 'trigger_type', v_trigger_type);
END;
$find_or_open$;

COMMENT ON FUNCTION silver.find_or_open_case(varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  '通用的查找或建立案件步骤：同一主体加同一案件类型只保留一个案件，已存在则复用。KYC 与 AML 共用。';

-- 验证案件：包装通用步骤。KYC 类发现的案件号要回填到数据质量问题表，所以要返回编号。
CREATE OR REPLACE FUNCTION silver.find_or_open_verification_case(
  p_case_type varchar,
  p_kyc_verification_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_verification_case$
  SELECT silver.find_or_open_case(
    'KYC', p_case_type, p_kyc_verification_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_verification_case$;

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  '查找或建立验证案件并返回案件编号。同一验证事件加同一案件类型只保留一个案件。';

-- AML 案件：数据质量问题表里没有对应列可回填，所以只建案、不回填。
CREATE OR REPLACE FUNCTION silver.find_or_open_aml_case(
  p_case_type varchar,
  p_aml_screening_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_aml_case$
  SELECT silver.find_or_open_case(
    'AML', p_case_type, p_aml_screening_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_aml_case$;

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  '查找或建立 AML 调查案件并返回案件编号。复用逻辑与验证案件一致。';

-- Dispatches a registered finding to the correct case table. Returns the
-- verification case identifier for KYC findings and NULL for AML findings,
-- because silver.data_quality_issue only carries a verification_case_id link.
CREATE OR REPLACE FUNCTION silver.resolve_compliance_case(
  p_entity_name varchar,
  p_case_type varchar,
  p_record_reference varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $resolve_case$
BEGIN
  IF p_entity_name = 'KYC_VERIFICATION_RECORD' THEN
    RETURN silver.find_or_open_verification_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
  ELSIF p_entity_name = 'AML_SCREENING_RESULT' THEN
    PERFORM silver.find_or_open_aml_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
    RETURN NULL;
  END IF;

  RAISE EXCEPTION 'Unsupported compliance entity %', p_entity_name;
END;
$resolve_case$;

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'Opens or reuses the case for one finding and returns the verification case link expected by silver.data_quality_issue.';

-- Opens or reuses a case for every open finding this module registered and links
-- the KYC findings to their verification case. Safe to rerun: the functions are
-- keyed on the event and case type, so a finding that already has its case
-- produces no further rows.
CREATE OR REPLACE PROCEDURE silver.publish_compliance_cases(
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $publish_cases$
DECLARE
  v_open_issues integer;
  v_linked_issues integer := 0;
BEGIN
  -- silver.data_quality_issue records the source reference of the event, while
  -- the case functions address the published record by its primary key, so the
  -- published identifier is resolved here.
  DROP TABLE IF EXISTS tmp_compliance_case_issue;
  CREATE TEMP TABLE tmp_compliance_case_issue ON COMMIT DROP AS
  SELECT
    issue.data_quality_issue_id,
    issue.batch_id,
    issue.record_reference AS source_record_reference,
    COALESCE(
      verification.kyc_verification_id,
      screening.aml_screening_id
    ) AS published_record_id,
    issue.entity_name,
    issue.rule_name,
    issue.issue_description,
    issue.severity,
    -- One mapping function keeps the report's rule-to-case-type requirement in a
    -- single place: 04_create_kyc_aml_validation.sql owns it.
    -- Only a rule that the report marks as reportable opens a case. A rule with
    -- no mapping (for example the LOW unresolved-identity notice) stays a quality
    -- record, because an identity that is still pending is not a compliance
    -- exception.
    silver.compliance_rule_case_type(issue.rule_name) AS case_type
  FROM silver.data_quality_issue issue
  LEFT JOIN silver.kyc_verification_record verification
    ON verification.source_system_id = issue.source_system_id
   AND verification.source_kyc_reference = issue.record_reference
  LEFT JOIN silver.aml_screening_result screening
    ON screening.source_system_id = issue.source_system_id
   AND screening.source_screening_reference = issue.record_reference
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
  ORDER BY issue.batch_id, issue.rule_name, issue.record_reference;
  SELECT count(*)::integer INTO v_open_issues FROM tmp_compliance_case_issue;
  IF EXISTS (
    SELECT 1
    FROM tmp_compliance_case_issue case_issue
    WHERE case_issue.published_record_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'A finding refers to an event that was withheld from Silver, so it has no case: %',
      (
        SELECT string_agg(case_issue.source_record_reference, ', ')
        FROM tmp_compliance_case_issue case_issue
        WHERE case_issue.published_record_id IS NULL
      );
  END IF;
  IF v_open_issues > 0 THEN
    UPDATE silver.data_quality_issue issue
    SET verification_case_id = silver.resolve_compliance_case(
      case_issue.entity_name,
      case_issue.case_type,
      case_issue.published_record_id,
      case_issue.rule_name,
      case_issue.issue_description,
      case_issue.severity
    )
    FROM tmp_compliance_case_issue case_issue
    WHERE issue.data_quality_issue_id = case_issue.data_quality_issue_id
      -- A rule without a case mapping stays a quality record only, so no case is
      -- opened or linked for it.
      AND case_issue.case_type IS NOT NULL;
    GET DIAGNOSTICS v_linked_issues = ROW_COUNT;
  END IF;
  RAISE NOTICE 'Compliance case publication: % open findings processed, % linked',
    v_open_issues,
    v_linked_issues;
END;
$publish_cases$;

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'Opens or reuses the compliance case for every open KYC/AML finding and links KYC findings to their verification case.';

-- Reconciles case status against the current evidence:
--   * an open finding that the current rules no longer produce is resolved;
--   * a verification case whose last open finding is resolved becomes RESOLVED;
--   * an AML case whose alert is no longer raised becomes CLOSED;
--   * a case that still has an open finding stays open, so an accumulating
--     exception keeps counting days instead of being closed and reopened.
CREATE OR REPLACE PROCEDURE silver.progress_compliance_cases(
  p_reference_date date DEFAULT current_date,
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $progress_cases$
DECLARE
  v_resolved_issues integer;
  v_resolved_verification_cases integer;
  v_closed_aml_cases integer;
BEGIN
  IF p_reference_date IS NULL THEN
    RAISE EXCEPTION 'A reference date is required to progress compliance cases';
  END IF;

  DROP TABLE IF EXISTS tmp_current_finding;

  CREATE TEMP TABLE tmp_current_finding ON COMMIT DROP AS
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_kyc_verification_issues(NULL::varchar, p_reference_date) finding
  UNION
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_aml_screening_issues(NULL::varchar, p_reference_date) finding;

  UPDATE silver.data_quality_issue issue
  SET
    resolved_at = clock_timestamp(),
    issue_status = 'RESOLVED'
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = issue.record_reference
        AND finding.rule_name = issue.rule_name
    );

  GET DIAGNOSTICS v_resolved_issues = ROW_COUNT;

  UPDATE silver.special_verification_case investigation
  SET
    case_status = 'RESOLVED',
    resolved_at = clock_timestamp(),
    resolution_outcome = left(
      concat(
        'All linked findings cleared by the Member 5 validation rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND EXISTS (
      SELECT 1
      FROM silver.data_quality_issue linked_issue
      WHERE linked_issue.verification_case_id = investigation.verification_case_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM silver.data_quality_issue open_issue
      WHERE open_issue.verification_case_id = investigation.verification_case_id
        AND open_issue.issue_status = 'OPEN'
    );

  GET DIAGNOSTICS v_resolved_verification_cases = ROW_COUNT;

  UPDATE silver.aml_case investigation
  SET
    case_status = 'CLOSED',
    closed_at = clock_timestamp(),
    case_outcome = left(
      concat(
        'Screening alert reviewed; no finding remained open under the Member 5 rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND investigation.aml_screening_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = investigation.aml_screening_id
    );

  GET DIAGNOSTICS v_closed_aml_cases = ROW_COUNT;

  RAISE NOTICE
    'Case progression at %: % findings resolved, % verification cases resolved, % AML cases closed',
    p_reference_date,
    v_resolved_issues,
    v_resolved_verification_cases,
    v_closed_aml_cases;
END;
$progress_cases$;

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'Resolves findings that the current rules no longer produce and closes the cases whose findings are all cleared.';
