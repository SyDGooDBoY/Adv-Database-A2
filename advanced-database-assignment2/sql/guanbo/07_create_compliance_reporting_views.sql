-- PostgreSQL 15+
-- Member 5: the KYC/AML Exception Report and the KYC status feeding it.
--
-- These views are the reporting interface for the compliance exception fact.
-- They are plain views rather than materialised views so a report always reads
-- the latest refreshed fact without a separate refresh step.

-- Rule from the report: kyc_status is VERIFIED only when all required checks are
-- successful and unexpired with no unresolved relevant discrepancy. Other
-- outcomes are INCOMPLETE, REVIEW_REQUIRED or UNKNOWN.
--
-- One row per golden customer, evaluated at p_reference_date. The view is
-- filtered on request; without a date it evaluates at current_date, which is
-- why the predicate is written as a parameterised function call.
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
  -- The status is computed in its own step so the table function's output
  -- parameter names cannot collide with the underlying column names.
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

-- The KYC/AML Exception Report: one row per compliance exception with the
-- originating case detail behind it. Cases whose identity is still unresolved
-- are retained through the left join, as the report requires.
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

-- Exception totals per customer and exception type, for the report's summary
-- block. Left joins keep cases whose dimension row is not available yet.
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
    -- Severity is a label, so the highest value is selected by explicit rank.
    -- Taking the alphabetically largest label would rank MEDIUM above HIGH.
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

-- Evidence path required by the report: every published exception can be traced
-- from the raw Bronze record through the Silver event to the case and the fact.
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
