-- PostgreSQL 15+
-- Member 5: the KYC/AML Exception Report's accumulating snapshot fact.
--
-- gold.fact_compliance_exception holds exactly one row per originating case:
--   * exactly one of verification_case_id and aml_case_id is populated, and it
--     must agree with exception_source_type;

-- The shared setup created fact_compliance_exception_index_14 and _15 as plain
-- unique indexes on verification_case_id and aml_case_id. PostgreSQL treats null
-- values as distinct in a unique index, but the fact stores exactly one case
-- reference per row, so every row leaves the other column null and only the
-- first row of each type could be inserted. Replacing them with partial unique
-- indexes keeps the "each case occurs once" rule while allowing the nulls.
DO $fact_indexes$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_index index_definition
    JOIN pg_class table_definition
      ON table_definition.oid = index_definition.indrelid
    JOIN pg_namespace table_schema
      ON table_schema.oid = table_definition.relnamespace
    WHERE table_schema.nspname = 'gold'
      AND table_definition.relname = 'fact_compliance_exception'
      AND index_definition.indisunique
      AND NOT index_definition.indpred IS NOT NULL
      AND index_definition.indnatts = 1
      AND index_definition.indkey[0] IN (
        (SELECT attnum FROM pg_attribute
          WHERE attrelid = table_definition.oid AND attname = 'verification_case_id'),
        (SELECT attnum FROM pg_attribute
          WHERE attrelid = table_definition.oid AND attname = 'aml_case_id')
      )
  ) THEN
    DROP INDEX IF EXISTS gold.fact_compliance_exception_index_14;
    DROP INDEX IF EXISTS gold.fact_compliance_exception_index_15;

    CREATE UNIQUE INDEX fact_compliance_exception_index_14
      ON gold.fact_compliance_exception (verification_case_id)
      WHERE verification_case_id IS NOT NULL;

    CREATE UNIQUE INDEX fact_compliance_exception_index_15
      ON gold.fact_compliance_exception (aml_case_id)
      WHERE aml_case_id IS NOT NULL;

    RAISE NOTICE 'Rebuilt fact_compliance_exception case indexes as partial unique indexes';
  ELSE
    RAISE NOTICE 'fact_compliance_exception case indexes already allow null case references';
  END IF;
END
$fact_indexes$;

CREATE OR REPLACE FUNCTION gold.compliance_exception_fact_id(
  p_exception_source_type varchar,
  p_case_id varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $fact_id$
  SELECT CASE
    WHEN p_case_id IS NULL OR p_case_id = '' THEN NULL
    WHEN p_exception_source_type = 'VERIFICATION'
      THEN 'FCE-V-' || upper(substr(md5('VERIFICATION:' || p_case_id), 1, 20))
    WHEN p_exception_source_type = 'AML'
      THEN 'FCE-A-' || upper(substr(md5('AML:' || p_case_id), 1, 20))
    ELSE NULL
  END;
$fact_id$;

COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  'Deterministic exception fact key for an originating case, so refreshing a case updates its existing fact row.';

CREATE OR REPLACE PROCEDURE gold.refresh_compliance_exception_fact(
  p_as_of_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $refresh_fact$
DECLARE
  v_open_cases integer;
  v_current_rows integer;
  v_removed_rows integer;
  v_verification_rows integer;
  v_aml_rows integer;
BEGIN
  IF p_as_of_date IS NULL THEN
    RAISE EXCEPTION 'An as-of date is required to calculate days_open';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM silver.special_verification_case investigation
    WHERE investigation.resolved_at IS NOT NULL
      AND investigation.resolved_at::date > p_as_of_date
  ) THEN
    RAISE WARNING
      'A verification case is resolved after the as-of date %; days_open for it will be reported as zero',
      p_as_of_date;
  END IF;

  SELECT
    count(*) FILTER (WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')),
    count(*)::integer
  INTO v_open_cases, v_verification_rows
  FROM silver.special_verification_case investigation;

  SELECT count(*)::integer
  INTO v_aml_rows
  FROM silver.aml_case investigation;

  DROP TABLE IF EXISTS tmp_compliance_exception_fact;

  -- 两类案件合成一张事实表。
  --
  -- 原先写成两个 UNION ALL 分支，每个分支各写一遍状态映射、客户代理键查找、
  -- 账龄计算和结案日选择——同一个口径写两遍，容易改一处漏一处。现在 UNION ALL
  -- 只负责"把两边的列名和取值统一"，后续计算只写一遍。
  CREATE TEMP TABLE tmp_compliance_exception_fact ON COMMIT DROP AS
  WITH exception_case AS (
    SELECT
      'VERIFICATION' AS source_type,
      investigation.verification_case_id AS verification_case_id,
      NULL::varchar AS aml_case_id,
      investigation.customer_id,
      investigation.case_type,
      investigation.case_status,
      investigation.severity,
      investigation.opened_at,
      investigation.resolved_at AS closed_at
    FROM silver.special_verification_case investigation

    UNION ALL

    SELECT
      'AML',
      NULL::varchar,
      investigation.aml_case_id,
      investigation.customer_id,
      investigation.case_type,
      investigation.case_status,
      investigation.risk_level,
      investigation.opened_at,
      investigation.closed_at
    FROM silver.aml_case investigation
  )
  SELECT
    gold.compliance_exception_fact_id(
      exception_case.source_type,
      COALESCE(exception_case.verification_case_id, exception_case.aml_case_id)
    ) AS exception_fact_id,
    dimension.customer_key,
    exception_case.verification_case_id,
    exception_case.aml_case_id,
    exception_case.source_type AS exception_source_type,
    exception_case.case_type AS exception_type,
    -- 异常状态是事实表自己对案件的看法，由案件状态映射而来
    CASE exception_case.case_status
      WHEN 'OPEN' THEN 'OPEN'
      WHEN 'IN_REVIEW' THEN 'IN_REVIEW'
      WHEN 'RESOLVED' THEN 'RESOLVED'
      ELSE 'CLOSED'
    END AS exception_status,
    exception_case.severity,
    exception_case.opened_at::date AS opened_date,
    exception_case.closed_at::date AS resolved_date,
    p_as_of_date AS as_of_date,
    -- 账龄 = 结案日（未结案取报告基准日）− 开案日，并按报告基准日封顶，避免出现
    -- "比报告期还久"的自相矛盾数字。resolved_date 仍记录真实结案日。
    GREATEST(
      LEAST(COALESCE(exception_case.closed_at::date, p_as_of_date), p_as_of_date)
        - exception_case.opened_at::date,
      0
    ) AS days_open,
    clock_timestamp() AS last_updated_at
  FROM exception_case
  LEFT JOIN LATERAL (
    SELECT customer_dimension.customer_key
    FROM gold.dim_customer customer_dimension
    WHERE customer_dimension.customer_id = exception_case.customer_id
      AND customer_dimension.current_flag
    ORDER BY customer_dimension.effective_from DESC, customer_dimension.customer_key DESC
    LIMIT 1
  ) dimension ON true;

  INSERT INTO gold.fact_compliance_exception (
    exception_fact_id,
    customer_key,
    verification_case_id,
    aml_case_id,
    exception_source_type,
    exception_type,
    exception_status,
    severity,
    opened_date,
    resolved_date,
    as_of_date,
    days_open,
    last_updated_at
  )
  SELECT
    staged.exception_fact_id,
    staged.customer_key,
    staged.verification_case_id,
    staged.aml_case_id,
    staged.exception_source_type,
    staged.exception_type,
    staged.exception_status,
    staged.severity,
    staged.opened_date,
    staged.resolved_date,
    staged.as_of_date,
    staged.days_open,
    staged.last_updated_at
  FROM tmp_compliance_exception_fact staged
  ON CONFLICT (exception_fact_id) DO UPDATE SET
    customer_key = EXCLUDED.customer_key,
    exception_type = EXCLUDED.exception_type,
    exception_status = EXCLUDED.exception_status,
    severity = EXCLUDED.severity,
    opened_date = EXCLUDED.opened_date,
    resolved_date = EXCLUDED.resolved_date,
    as_of_date = EXCLUDED.as_of_date,
    days_open = EXCLUDED.days_open,
    last_updated_at = EXCLUDED.last_updated_at;

  -- A fact row whose originating case no longer exists would break the rule that
  -- each case appears exactly once, so it is removed when it goes stale.
  DELETE FROM gold.fact_compliance_exception fact
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.special_verification_case investigation
    WHERE investigation.verification_case_id = fact.verification_case_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM silver.aml_case investigation
    WHERE investigation.aml_case_id = fact.aml_case_id
  );

  GET DIAGNOSTICS v_removed_rows = ROW_COUNT;

  RAISE NOTICE
    'Compliance exception fact refreshed at %: % verification cases (% open), % AML cases, % stale facts removed',
    p_as_of_date,
    v_verification_rows,
    v_open_cases,
    v_aml_rows,
    v_removed_rows;
END;
$refresh_fact$;

COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  'Rebuilds the accumulating compliance exception fact for both case types, updating open cases in place and recalculating days_open to the as-of date.';
