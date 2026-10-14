-- PostgreSQL 15+
-- Member 5：合规异常报表。定义异常报表、异常汇总、数据血缘三个视图，
-- 以及按报告规则求值的客户 KYC 状态函数。
-- 用普通视图而非物化视图，报表直接读到最新刷新的事实表，无需额外刷新步骤。

-- 报告定义的 KYC 状态规则：只有全部所需验证成功且未过期、且没有未结的相关异常，
-- 才是 VERIFIED；其余为 INCOMPLETE、REVIEW_REQUIRED 或 UNKNOWN。
-- 每个金客户一行，按传入的基准日求值，所以做成带参数的函数而不是固定视图。
CREATE OR REPLACE FUNCTION silver.customer_kyc_status(
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  customer_id varchar,
  customer_full_name varchar,
  verification_count integer,
  latest_verification_date timestamp,
  latest_verification_status varchar,
  latest_expiry_date date,
  reusable_verification_count integer,
  aml_alert_count integer,
  open_exception_count integer,
  kyc_status varchar
)
LANGUAGE sql
STABLE
AS $kyc_status$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  verification AS (
    SELECT
      record.customer_id,
      count(*)::integer AS verification_count,
      max(record.verification_date) AS latest_verification_date,
      count(*) FILTER (
        WHERE record.verification_status = 'VERIFIED'
          AND (record.expiry_date IS NULL OR record.expiry_date >= reference_date.as_of_date)
      )::integer AS reusable_verification_count
    FROM silver.kyc_verification_record record
    CROSS JOIN reference_date
    WHERE record.customer_id IS NOT NULL
    GROUP BY record.customer_id
  ),
  latest_verification AS (
    SELECT DISTINCT ON (record.customer_id)
      record.customer_id,
      record.verification_status,
      record.expiry_date
    FROM silver.kyc_verification_record record
    WHERE record.customer_id IS NOT NULL
    ORDER BY
      record.customer_id,
      record.verification_date DESC,
      record.kyc_verification_id DESC
  ),
  screening AS (
    SELECT
      record.customer_id,
      count(*) FILTER (
        WHERE record.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH')
      )::integer AS aml_alert_count
    FROM silver.aml_screening_result record
    WHERE record.customer_id IS NOT NULL
    GROUP BY record.customer_id
  ),
  investigation AS (
    SELECT
      investigation_case.customer_id,
      count(*)::integer AS open_exception_count
    FROM (
      SELECT
        verification_case.customer_id,
        verification_case.case_status
      FROM silver.special_verification_case verification_case
      UNION ALL
      SELECT
        aml_case.customer_id,
        aml_case.case_status
      FROM silver.aml_case aml_case
    ) investigation_case
    WHERE investigation_case.case_status IN ('OPEN', 'IN_REVIEW')
      AND investigation_case.customer_id IS NOT NULL
    GROUP BY investigation_case.customer_id
  ),
  -- 状态单独一步算，避免表函数的输出列名与底层列名冲突。
  evaluated_customer AS (
    SELECT
      customer.customer_id,
      customer.customer_full_name,
      COALESCE(verification.verification_count, 0) AS verification_count,
      verification.latest_verification_date,
      latest_verification.verification_status,
      latest_verification.expiry_date,
      COALESCE(verification.reusable_verification_count, 0) AS reusable_verification_count,
      COALESCE(screening.aml_alert_count, 0) AS aml_alert_count,
      COALESCE(investigation.open_exception_count, 0) AS open_exception_count
    FROM silver.customer_master customer
    LEFT JOIN verification ON verification.customer_id = customer.customer_id
    LEFT JOIN latest_verification ON latest_verification.customer_id = customer.customer_id
    LEFT JOIN screening ON screening.customer_id = customer.customer_id
    LEFT JOIN investigation ON investigation.customer_id = customer.customer_id
  )
  SELECT
    evaluated_customer.customer_id::varchar,
    evaluated_customer.customer_full_name::varchar,
    evaluated_customer.verification_count,
    evaluated_customer.latest_verification_date,
    evaluated_customer.verification_status::varchar,
    evaluated_customer.expiry_date,
    evaluated_customer.reusable_verification_count,
    evaluated_customer.aml_alert_count,
    evaluated_customer.open_exception_count,
    CASE
      WHEN evaluated_customer.verification_count = 0
        AND evaluated_customer.aml_alert_count = 0
        THEN 'UNKNOWN'
      WHEN evaluated_customer.open_exception_count > 0
        THEN 'REVIEW_REQUIRED'
      WHEN evaluated_customer.reusable_verification_count > 0
        THEN 'VERIFIED'
      ELSE 'INCOMPLETE'
    END::varchar AS kyc_status
  FROM evaluated_customer;
$kyc_status$;

COMMENT ON FUNCTION silver.customer_kyc_status(date) IS
  'One row per golden customer with the report-defined KYC status at a reference date: VERIFIED, INCOMPLETE, REVIEW_REQUIRED or UNKNOWN.';

-- 异常报表主视图：一行一笔异常，并带出来源案件的明细。
-- 身份未确认的行通过左连接保留，不丢弃。
CREATE OR REPLACE VIEW gold.vw_kyc_aml_exception_report AS
SELECT
  fact.exception_fact_id,
  fact.exception_source_type,
  fact.exception_type,
  fact.exception_status,
  fact.severity,
  fact.opened_date,
  fact.resolved_date,
  fact.as_of_date,
  fact.days_open,
  fact.customer_key,
  COALESCE(dimension.customer_id, verification_case.customer_id, aml_case.customer_id)
    AS customer_id,
  COALESCE(
    dimension.customer_full_name,
    customer.customer_full_name,
    'Unresolved identity'
  ) AS customer_name,
  fact.verification_case_id,
  fact.aml_case_id,
  COALESCE(verification_case.trigger_type, aml_case.trigger_type) AS trigger_type,
  COALESCE(verification_case.case_reason, aml_case.trigger_reference) AS case_reason,
  verification_case.kyc_verification_id,
  aml_case.aml_screening_id,
  COALESCE(verification_case.resolution_outcome, aml_case.case_outcome) AS case_outcome,
  fact.last_updated_at
FROM gold.fact_compliance_exception fact
LEFT JOIN gold.dim_customer dimension
  ON dimension.customer_key = fact.customer_key
LEFT JOIN silver.special_verification_case verification_case
  ON verification_case.verification_case_id = fact.verification_case_id
LEFT JOIN silver.aml_case aml_case
  ON aml_case.aml_case_id = fact.aml_case_id
LEFT JOIN silver.customer_master customer
  ON customer.customer_id = COALESCE(
    verification_case.customer_id,
    aml_case.customer_id
  );

COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'One row per compliance exception with its originating case detail; unresolved identities are retained rather than filtered out.';

-- 异常汇总视图：按客户与异常类型统计，供报表汇总区使用。
CREATE OR REPLACE VIEW gold.vw_compliance_exception_summary AS
WITH customer_exception AS (
  SELECT
    COALESCE(
      dimension.customer_id,
      verification_case.customer_id,
      aml_case.customer_id
    ) AS customer_id,
    COALESCE(customer.customer_full_name, 'Unresolved identity') AS customer_name,
    fact.exception_source_type,
    fact.exception_type,
    count(*)::integer AS exception_count,
    count(*) FILTER (
      WHERE fact.exception_status IN ('OPEN', 'IN_REVIEW')
    )::integer AS open_exception_count,
    count(*) FILTER (
      WHERE fact.exception_status IN ('RESOLVED', 'CLOSED')
    )::integer AS resolved_exception_count,
    max(fact.days_open) AS longest_days_open,
    max(fact.as_of_date) AS as_of_date,
    -- 严重程度是文字标签，按显式等级取最高；按字母排序会把 MEDIUM 排在 HIGH 之上。
    max(
      CASE fact.severity
        WHEN 'CRITICAL' THEN 4
        WHEN 'HIGH' THEN 3
        WHEN 'MEDIUM' THEN 2
        WHEN 'LOW' THEN 1
        ELSE 0
      END
    ) AS severity_rank
  FROM gold.fact_compliance_exception fact
  LEFT JOIN gold.dim_customer dimension
    ON dimension.customer_key = fact.customer_key
  LEFT JOIN silver.special_verification_case verification_case
    ON verification_case.verification_case_id = fact.verification_case_id
  LEFT JOIN silver.aml_case aml_case
    ON aml_case.aml_case_id = fact.aml_case_id
  LEFT JOIN silver.customer_master customer
    ON customer.customer_id = COALESCE(
      verification_case.customer_id,
      aml_case.customer_id
    )
  GROUP BY
    COALESCE(
      dimension.customer_id,
      verification_case.customer_id,
      aml_case.customer_id
    ),
    COALESCE(customer.customer_full_name, 'Unresolved identity'),
    fact.exception_source_type,
    fact.exception_type
)
SELECT
  customer_exception.customer_id,
  customer_exception.customer_name,
  customer_exception.exception_source_type,
  customer_exception.exception_type,
  customer_exception.exception_count,
  customer_exception.open_exception_count,
  customer_exception.resolved_exception_count,
  customer_exception.longest_days_open,
  CASE customer_exception.severity_rank
    WHEN 4 THEN 'CRITICAL'
    WHEN 3 THEN 'HIGH'
    WHEN 2 THEN 'MEDIUM'
    WHEN 1 THEN 'LOW'
    ELSE 'UNKNOWN'
  END AS highest_severity,
  customer_exception.as_of_date
FROM customer_exception;

COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  'Exception counts and longest open duration per customer, source type and exception type.';

-- 数据血缘视图：把 Bronze 原始记录 → Silver 事件 → 案件 → 异常事实串成一条链路。
CREATE OR REPLACE VIEW silver.vw_kyc_aml_exception_lineage AS
SELECT
  lineage.lineage_id,
  lineage.batch_id,
  lineage.source_record_reference AS bronze_record_reference,
  lineage.target_record_reference AS published_event_reference,
  lineage.target_entity_name,
  lineage.transformation_name,
  lineage.transformation_timestamp,
  COALESCE(
    verification_case.verification_case_id,
    aml_case.aml_case_id
  ) AS case_reference,
  COALESCE(verification_case.case_type, aml_case.case_type) AS case_type,
  gold.compliance_exception_fact_id(
    CASE
      WHEN verification_case.verification_case_id IS NOT NULL THEN 'VERIFICATION'
      ELSE 'AML'
    END,
    COALESCE(verification_case.verification_case_id, aml_case.aml_case_id)
  ) AS exception_fact_id
FROM silver.data_lineage_record lineage
LEFT JOIN silver.special_verification_case verification_case
  ON verification_case.kyc_verification_id = lineage.target_record_reference
LEFT JOIN silver.aml_case aml_case
  ON aml_case.aml_screening_id = lineage.target_record_reference
WHERE lineage.transformation_name IN (
  'PUBLISH_KYC_VERIFICATION_EVENT',
  'PUBLISH_AML_SCREENING_EVENT'
);

COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  'Traceability path from each retained Bronze KYC/AML record through its published Silver event to the compliance case and exception fact row.';
