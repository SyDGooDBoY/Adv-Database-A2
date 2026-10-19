-- PRESENTATION FILE 
-- =====================================================================
-- @@BRONZE  (Member 1 – ingestion)
-- =====================================================================

-- @@B1 RUN: 6 batches, 2 dates, all SUCCEEDED, watermark per batch
SELECT batch_id, source_system_id, load_type, load_status, records_received, watermark_end
FROM bronze.ingestion_batch ORDER BY watermark_end, batch_id;

-- @@B2 RUN: raw data kept as received
SELECT * FROM bronze.raw_loan_snapshot ORDER BY 1 LIMIT 10;

-- @@B3 RUN: failure -> retry timeline
WITH retry_evidence AS (
  SELECT
    batch.*,
    silver.count_bronze_batch_records(batch.batch_id) AS retained_bronze_rows,
    (
      SELECT count(*)
      FROM bronze.cdc_change_event event
      WHERE event.batch_id = batch.batch_id
    ) AS retained_cdc_events,
    issue.detected_at AS failure_recorded_at,
    issue.resolved_at AS retry_completed_at,
    issue.issue_status AS final_issue_status
  FROM silver.ingestion_batch batch
  JOIN silver.data_quality_issue issue
    ON issue.batch_id = batch.batch_id
   AND issue.rule_name = 'forced_failure_demo'
  WHERE batch.batch_id = 'B2-CRM'
)
SELECT
  stage,
  batch_status,
  processed_rows,
  retained_bronze_rows,
  retained_cdc_events,
  committed_watermark,
  issue_status,
  event_time
FROM (
  SELECT
    1 AS display_order,
    '1. FORCED FAILURE' AS stage,
    'FAILED' AS batch_status,
    0 AS processed_rows,
    retained_bronze_rows,
    retained_cdc_events,
    watermark_start AS committed_watermark,
    'OPEN' AS issue_status,
    failure_recorded_at AS event_time
  FROM retry_evidence

  UNION ALL

  SELECT
    2 AS display_order,
    '2. RETRY SUCCEEDED' AS stage,
    load_status AS batch_status,
    records_processed AS processed_rows,
    retained_bronze_rows,
    retained_cdc_events,
    watermark_end AS committed_watermark,
    final_issue_status AS issue_status,
    retry_completed_at AS event_time
  FROM retry_evidence
) timeline
ORDER BY display_order;

-- =====================================================================
-- @@SILVER  (Member 2 matching, Member 3 golden record, Member 5 KYC/AML, Member 4 financial load)
-- =====================================================================

-- @@S1 RUN: matching result (24 ACCEPTED, 1 PENDING_REVIEW)
SELECT match_status, manual_review_flag, count(*) AS records
FROM silver.customer_source_match WHERE is_current_match GROUP BY 1, 2 ORDER BY 1;

-- @@S2 RUN: 13 unified customers (Member 3 survivorship)
SELECT customer_id, customer_full_name, customer_status FROM silver.customer_master ORDER BY 2;

-- @@S3 RUN: KYC/AML result per customer (Member 5)
SELECT * FROM gold.customer_compliance(DATE '2026-09-15') ORDER BY 1;

-- KEY CODE  module4_dan/01_load_silver_financials.sql – only ACCEPTED matches are loaded;
-- anything else is logged as a data quality issue instead of being dropped silently.
-- @@S4 RUN: LOAN-002 logged on both dates
SELECT validation_run_id, entity_name, record_reference, issue_description, issue_status
FROM silver.data_quality_issue WHERE validation_run_id LIKE 'FIN-%' ORDER BY 1;

-- =====================================================================
-- @@GOLD  (Member 4 star schema + Member 5 compliance exceptions)
-- =====================================================================

-- @@G1 RUN: star schema – fact joined to dimension, two dates
SELECT f.snapshot_date, d.customer_full_name, f.total_debt, f.risk_score, f.risk_rating, f.kyc_status, f.aml_risk_level
FROM gold.fact_customer_snapshot f JOIN gold.dim_customer d ON d.customer_key = f.customer_key
ORDER BY d.customer_full_name, f.snapshot_date;

-- @@G2 RUN: portfolio by rating (15 Sep: LOW 4 / MEDIUM 4 / HIGH 2)
SELECT * FROM gold.v_portfolio_risk_distribution ORDER BY snapshot_date, risk_rating;

-- @@G3 RUN: what changed between the dates (Olivia LOW -> MEDIUM, Mia new)
SELECT coalesce(a.customer_full_name, b.customer_full_name) AS customer,
       a.risk_rating AS rating_0901, b.risk_rating AS rating_0915,
       a.total_debt AS debt_0901, b.total_debt AS debt_0915
FROM (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-01') a
FULL JOIN (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-15') b USING (customer_id)
WHERE a.risk_rating IS DISTINCT FROM b.risk_rating OR a.total_debt IS DISTINCT FROM b.total_debt
ORDER BY 1;

-- @@G4 RUN: compliance exceptions (Member 5)
SELECT * FROM gold.vw_compliance_exception_summary;

-- =====================================================================
-- @@DASHBOARD  switch to http://localhost:8501 (click "Refresh data" first)
-- =====================================================================
