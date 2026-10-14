-- PostgreSQL 15+
-- Member 5 验收测试：断言业务结果，并输出可直接截图的报表查询。
-- 先按文件名顺序执行 00-07，再依次调用：
--
--   CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');
--   CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');
--   CALL silver.publish_compliance_cases();
--   CALL silver.progress_compliance_cases(DATE '2026-09-30');
--   CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');
--
-- 基准日取 2026-09-30，晚于两个批次，因此 VFY-012（有效期 2026-08-15）正确判为过期。

DO $member5_tests$
DECLARE
  v_count integer;
  v_other_count integer;
  v_text text;
  v_reference_date date := DATE '2026-09-30';
  v_kyc_published integer;
  v_aml_published integer;
  v_b2_aml_published integer;
  v_verification_cases integer;
  v_aml_cases integer;
  v_fact_rows integer;
  v_orphan_rows integer;
  v_duplicate_cases integer;
  v_pending_links integer;
  v_cases_before integer;
  v_cases_after integer;
BEGIN
  -- 1. 两个批次的事件都已发布，包括 Member 1 因 CDC 事件 operation_type 为空而置为 FAILED 的那批。
  SELECT count(*)::integer INTO v_kyc_published
  FROM silver.kyc_verification_record
  WHERE source_system_id = 'AMLKYC';

  IF v_kyc_published <> 9 THEN
    RAISE EXCEPTION 'Expected 9 published KYC verification records, found %', v_kyc_published;
  END IF;

  SELECT count(*)::integer INTO v_aml_published
  FROM silver.aml_screening_result
  WHERE source_system_id = 'AMLKYC';

  IF v_aml_published <> 10 THEN
    RAISE EXCEPTION 'Expected 10 published AML screening results, found %', v_aml_published;
  END IF;


  SELECT count(*)::integer INTO v_b2_aml_published
  FROM silver.aml_screening_result screening
  JOIN silver.data_lineage_record lineage
    ON lineage.target_record_reference = screening.aml_screening_id
  WHERE lineage.batch_id = 'B2-AMLKYC';

  IF v_b2_aml_published <> 1 THEN
    RAISE EXCEPTION
      'Expected the failed B2-AMLKYC batch to contribute 1 screening event, found %',
      v_b2_aml_published;
  END IF;

  -- 2. 每条事件都仍然有主体引用。
  SELECT count(*)::integer INTO v_count
  FROM silver.kyc_verification_record
  WHERE customer_id IS NULL AND source_customer_record_id IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Blocking KYC subject rule did not withhold % records', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.aml_screening_result
  WHERE customer_id IS NULL AND source_customer_record_id IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Blocking AML subject rule did not withhold % records', v_count;
  END IF;

  -- 3. 已发布的事件不应登记任何阻断级问题。
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND severity = 'BLOCKING';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Found % blocking issues on published events', v_count;
  END IF;

  -- 4. 演示数据应当产生的可报告发现。
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'KYC_VERIFICATION_INCOMPLETE';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 KYC gap finding (VFY-004), found %', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'KYC_VERIFICATION_EXPIRED';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 expired verification finding (VFY-012), found %', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'AML_REVIEW_REQUIRED';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 AML screening alert finding (SCR-005-2), found %', v_count;
  END IF;

  -- 5. 案件类型只能是报告规定的取值。
  SELECT count(*)::integer INTO v_count
  FROM silver.special_verification_case
  WHERE case_type IN ('KYC_GAP', 'IDENTITY_MISMATCH', 'STATUS_DISCREPANCY');

  SELECT count(*)::integer INTO v_other_count
  FROM silver.special_verification_case;

  IF v_count <> v_other_count THEN
    RAISE EXCEPTION
      'Found % verification cases outside the report case types, expected 0',
      v_other_count - v_count;
  END IF;

  SELECT count(*)::integer INTO v_verification_cases FROM silver.special_verification_case;
  SELECT count(*)::integer INTO v_aml_cases FROM silver.aml_case;

  -- 只有资料缺口与状态矛盾两类规则会建案；LOW 级的"身份尚未合并"只是提示，
  -- 仍然只登记为质量问题。
  IF v_verification_cases <> 2 THEN
    RAISE EXCEPTION 'Expected 2 verification cases, found %', v_verification_cases;
  END IF;

  IF v_aml_cases <> 1 THEN
    RAISE EXCEPTION 'Expected 1 AML case, found %', v_aml_cases;
  END IF;

  -- 6. 凡映射到案件类型的未结发现，都必须有对应案件。
  SELECT count(*)::integer INTO v_pending_links
  FROM silver.data_quality_issue issue
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name = 'KYC_VERIFICATION_RECORD'
    AND silver.compliance_rule_case_type(issue.rule_name) IS NOT NULL
    AND issue.verification_case_id IS NULL;

  IF v_pending_links <> 0 THEN
    RAISE EXCEPTION
      '% reportable open KYC findings have no verification case',
      v_pending_links;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue issue
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND silver.compliance_rule_case_type(issue.rule_name) IS NULL
    AND issue.verification_case_id IS NOT NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% non-reportable findings were linked to a verification case',
      v_count;
  END IF;

  -- 案件必须指向该发现所属的事件，不能指向别的事件。
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue issue
  JOIN silver.special_verification_case investigation
    ON investigation.verification_case_id = issue.verification_case_id
  JOIN silver.kyc_verification_record verification
    ON verification.kyc_verification_id = investigation.kyc_verification_id
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.entity_name = 'KYC_VERIFICATION_RECORD'
    AND verification.source_kyc_reference <> issue.record_reference;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% verification cases are linked to a different event than their finding',
      v_count;
  END IF;

  -- 7. 案件状态与结案时间一致。
  SELECT count(*)::integer INTO v_count
  FROM silver.special_verification_case
  WHERE (case_status IN ('RESOLVED', 'CLOSED') AND resolved_at IS NULL)
     OR (case_status IN ('OPEN', 'IN_REVIEW') AND resolved_at IS NOT NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% verification cases have an inconsistent status and resolution', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.aml_case
  WHERE (case_status = 'CLOSED' AND closed_at IS NULL)
     OR (case_status <> 'CLOSED' AND closed_at IS NOT NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% AML cases have an inconsistent status and closing date', v_count;
  END IF;

  -- 8. 累积事实表每个来源案件只有一行。
  SELECT count(*)::integer INTO v_fact_rows FROM gold.fact_compliance_exception;

  IF v_fact_rows <> v_verification_cases + v_aml_cases THEN
    RAISE EXCEPTION
      'Exception fact holds % rows for % originating cases',
      v_fact_rows,
      v_verification_cases + v_aml_cases;
  END IF;

  SELECT count(*)::integer INTO v_duplicate_cases
  FROM (
    SELECT verification_case_id
    FROM gold.fact_compliance_exception
    WHERE verification_case_id IS NOT NULL
    GROUP BY verification_case_id
    HAVING count(*) > 1
    UNION ALL
    SELECT aml_case_id
    FROM gold.fact_compliance_exception
    WHERE aml_case_id IS NOT NULL
    GROUP BY aml_case_id
    HAVING count(*) > 1
  ) duplicated;

  IF v_duplicate_cases <> 0 THEN
    RAISE EXCEPTION '% originating cases appear more than once in the fact', v_duplicate_cases;
  END IF;

  -- 9. 每行事实恰好一个案件引用，且与来源类型一致。
  SELECT count(*)::integer INTO v_orphan_rows
  FROM gold.fact_compliance_exception
  WHERE (verification_case_id IS NULL AND aml_case_id IS NULL)
     OR (verification_case_id IS NOT NULL AND aml_case_id IS NOT NULL);

  IF v_orphan_rows <> 0 THEN
    RAISE EXCEPTION '% exception fact rows do not carry exactly one case', v_orphan_rows;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE (exception_source_type = 'VERIFICATION' AND verification_case_id IS NULL)
     OR (exception_source_type = 'AML' AND aml_case_id IS NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows disagree with exception_source_type', v_count;
  END IF;

  -- 10. 账龄与所依据的日期一致，且不超过报告基准日。
  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open <> GREATEST(
    LEAST(COALESCE(resolved_date, as_of_date), as_of_date) - opened_date,
    0
  );

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows have an incorrect days_open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open < 0;

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows have a negative days_open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open > as_of_date - opened_date;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% exception fact rows are older than the reporting date',
      v_count;
  END IF;

  -- 11. 身份未确认的异常要出现在报表里，不能被丢掉。
  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE customer_key IS NULL;

  IF v_count <> v_fact_rows THEN
    RAISE EXCEPTION
      'Expected every exception to lack a dimension key while identity is unresolved, % of % rows have one',
      v_fact_rows - v_count,
      v_fact_rows;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.vw_kyc_aml_exception_report
  WHERE customer_name IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'The exception report dropped % rows with an unresolved identity', v_count;
  END IF;

  -- 12. 以下规则在演示数据上不应触发。
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name IN (
      'KYC_IDENTITY_LINK_MISMATCH',
      'AML_IDENTITY_LINK_MISMATCH',
      'AML_CLEAR_SCREENING_SCORE_INCONSISTENT',
      'AML_CLEAR_SCREENING_WITH_REVIEW',
      'KYC_VERIFICATION_TYPE_INVALID',
      'KYC_VERIFICATION_STATUS_INVALID',
      'AML_SCREENING_TYPE_INVALID',
      'AML_SCREENING_RESULT_INVALID',
      'AML_MATCH_SCORE_OUT_OF_RANGE'
    );

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Supplied data unexpectedly raised % inconsistent-data findings', v_count;
  END IF;

  -- 13. KYC 状态符合报告规则：有未结异常的客户不能是 VERIFIED。
  SELECT count(*)::integer INTO v_count
  FROM silver.customer_kyc_status(v_reference_date)
  WHERE kyc_status = 'VERIFIED'
    AND open_exception_count > 0;

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% customers are reported VERIFIED while an exception is open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.customer_kyc_status(v_reference_date)
  WHERE kyc_status NOT IN ('VERIFIED', 'INCOMPLETE', 'REVIEW_REQUIRED', 'UNKNOWN');

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% customers have a KYC status outside the report values', v_count;
  END IF;

  -- 14. 重复执行不产生重复数据。
  SELECT count(*)::integer INTO v_cases_before FROM silver.special_verification_case;

  CALL silver.publish_compliance_cases();
  CALL silver.publish_compliance_cases();

  SELECT count(*)::integer INTO v_cases_after FROM silver.special_verification_case;

  IF v_cases_after <> v_cases_before THEN
    RAISE EXCEPTION
      'Republishing cases created % additional verification cases',
      v_cases_after - v_cases_before;
  END IF;

  SELECT count(*)::integer INTO v_cases_before FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%';

  CALL silver.process_kyc_aml_batch('B1-AMLKYC', v_reference_date);

  SELECT count(*)::integer INTO v_cases_after FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%';

  IF v_cases_after <> v_cases_before THEN
    RAISE EXCEPTION
      'Reprocessing batch B1-AMLKYC changed the issue count from % to %',
      v_cases_before,
      v_cases_after;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.kyc_verification_record
  WHERE source_system_id = 'AMLKYC';

  IF v_count <> 9 THEN
    RAISE EXCEPTION 'Reprocessing duplicated KYC events; found %', v_count;
  END IF;

  -- 15. 刷新未结案件时更新原行而不是新增行。
  CALL gold.refresh_compliance_exception_fact(v_reference_date);

  SELECT count(*)::integer INTO v_count FROM gold.fact_compliance_exception;

  IF v_count <> v_fact_rows THEN
    RAISE EXCEPTION
      'Refreshing the fact changed its row count from % to %',
      v_fact_rows,
      v_count;
  END IF;

  RAISE NOTICE 'All Member 5 acceptance tests passed';
END
$member5_tests$;

-- 报表输出：以下查询的结果可直接用于报告与截图。

-- KYC/AML 异常报表。
SELECT
  exception_source_type,
  exception_type,
  exception_status,
  severity,
  opened_date,
  resolved_date,
  as_of_date,
  days_open,
  customer_id,
  customer_name,
  case_reason
FROM gold.vw_kyc_aml_exception_report
ORDER BY exception_source_type, exception_type, opened_date;

-- 异常汇总。
SELECT *
FROM gold.vw_compliance_exception_summary
ORDER BY open_exception_count DESC, longest_days_open DESC;

-- 按报告规则求出的客户 KYC 状态。
SELECT
  customer_id,
  customer_full_name,
  verification_count,
  reusable_verification_count,
  aml_alert_count,
  open_exception_count,
  kyc_status
FROM silver.customer_kyc_status(DATE '2026-09-30')
ORDER BY kyc_status, customer_id;

-- 校验发现（含按设计未触发的规则）。
SELECT
  rule_name,
  entity_name,
  severity,
  count(*) AS finding_count,
  count(*) FILTER (WHERE issue_status = 'OPEN') AS open_count
FROM silver.data_quality_issue
WHERE validation_run_id LIKE 'KYC-AML-M5-%'
GROUP BY rule_name, entity_name, severity
ORDER BY rule_name;

-- 案件及其清除证据。
SELECT
  investigation.verification_case_id AS case_id,
  'VERIFICATION' AS case_source,
  investigation.case_type,
  investigation.case_status,
  investigation.severity,
  investigation.opened_at::date AS opened_date,
  investigation.resolved_at::date AS resolved_date,
  investigation.kyc_verification_id AS source_event
FROM silver.special_verification_case investigation
UNION ALL
SELECT
  investigation.aml_case_id,
  'AML',
  investigation.case_type,
  investigation.case_status,
  investigation.risk_level,
  investigation.opened_at::date,
  investigation.closed_at::date,
  investigation.aml_screening_id
FROM silver.aml_case investigation
ORDER BY case_source, case_type, case_id;

-- 从保留的原始记录到所报异常的追溯链路。
SELECT
  bronze_record_reference,
  batch_id,
  published_event_reference,
  target_entity_name,
  case_reference,
  case_type,
  exception_fact_id
FROM silver.vw_kyc_aml_exception_lineage
ORDER BY batch_id, bronze_record_reference;
