-- Step 4: Assess each customer's risk from exposure and Member5's KYC/AML results.
-- Run: CALL silver.assess_customer_risk(DATE '2026-09-15', '<scorecard json>');

BEGIN;

-- Return each customer's KYC status and AML level on a date.
CREATE OR REPLACE FUNCTION gold.customer_compliance(p_date date)
RETURNS TABLE (customer_id varchar(50), kyc_status varchar(30), aml_risk_level varchar(30))
LANGUAGE sql STABLE AS $$
  SELECT c.customer_id,
         -- KYC: latest verification, EXPIRED if past expiry, else UNKNOWN.
         COALESCE((SELECT CASE WHEN k.expiry_date < p_date THEN 'EXPIRED' ELSE k.verification_status END
                   FROM silver.kyc_verification_record k
                   WHERE k.customer_id = c.customer_id AND k.verification_date < p_date + 1
                   ORDER BY k.verification_date DESC LIMIT 1), 'UNKNOWN'),
         -- AML: latest open case, else latest screening, else UNKNOWN.
         COALESCE((SELECT a.risk_level FROM silver.aml_case a
                   WHERE a.customer_id = c.customer_id AND a.opened_at < p_date + 1
                     AND (a.closed_at IS NULL OR a.closed_at >= p_date + 1)
                   ORDER BY a.opened_at DESC LIMIT 1),
                  (SELECT s.screening_result FROM silver.aml_screening_result s
                   WHERE s.customer_id = c.customer_id AND s.screening_date < p_date + 1
                   ORDER BY s.screening_date DESC LIMIT 1),
                  'UNKNOWN')
  FROM silver.customer_master c;
$$;

-- Score each customer with a weighted scorecard and save the result.
CREATE OR REPLACE PROCEDURE silver.assess_customer_risk(p_date date, p_rules jsonb)
LANGUAGE plpgsql AS $$
DECLARE
  bad record;
BEGIN
  -- Stop if the scorecard JSON is missing a section.
  IF p_rules->>'rule_name' IS NULL OR p_rules->>'rule_version' IS NULL
     OR jsonb_typeof(p_rules->'base_score') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_rules->'kyc_points') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_rules->'aml_points') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_rules->'exposure_bands') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_rules->'rating_bands') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Scorecard JSON needs rule_name, rule_version, base_score, kyc_points, aml_points, exposure_bands and rating_bands';
  END IF;

  -- Stop if any KYC or AML value is missing its points or rating.
  IF EXISTS (SELECT 1 FROM (SELECT value FROM jsonb_each(p_rules->'kyc_points')
                            UNION ALL SELECT value FROM jsonb_each(p_rules->'aml_points')) v
             WHERE NOT jsonb_strip_nulls(v.value) ?& ARRAY['points', 'rating']) THEN
    RAISE EXCEPTION 'Each KYC and AML value needs points and rating';
  END IF;

  -- Score = base + KYC points + AML points + exposure points, capped at 100.
  DROP TABLE IF EXISTS tmp_risk;
  CREATE TEMP TABLE tmp_risk ON COMMIT DROP AS
  WITH scored AS (
    SELECT f.customer_id, f.total_credit_exposure, c.kyc_status, c.aml_risk_level,
           p_rules->'kyc_points'->c.kyc_status AS kyc,
           p_rules->'aml_points'->c.aml_risk_level AS aml,
           -- Exposure only counts when nothing is known about KYC and AML.
           CASE WHEN c.kyc_status = 'UNKNOWN' AND c.aml_risk_level = 'UNKNOWN' THEN
             (SELECT jsonb_agg(b) FROM jsonb_array_elements(p_rules->'exposure_bands') b
              WHERE f.total_credit_exposure >= (b->>'min')::numeric
                AND (b->>'max' IS NULL OR f.total_credit_exposure < (b->>'max')::numeric))
           ELSE '[{"points": 0}]'::jsonb END AS bands
    FROM gold.customer_financials(p_date) f
    JOIN gold.customer_compliance(p_date) c ON c.customer_id = f.customer_id
    WHERE f.total_credit_exposure IS NOT NULL
  ), totals AS (
    SELECT s.*, least((p_rules->>'base_score')::numeric + (s.kyc->>'points')::numeric
                      + (s.aml->>'points')::numeric + (s.bands->0->>'points')::numeric, 100) AS score
    FROM scored s
  )
  SELECT t.*,
         (SELECT jsonb_agg(r->>'rating') FROM jsonb_array_elements(p_rules->'rating_bands') r
          WHERE t.score >= (r->>'min')::numeric
            AND (r->>'max' IS NULL OR t.score < (r->>'max')::numeric)) AS ratings,
         concat_ws('; ', t.kyc->>'reason', t.aml->>'reason', t.bands->0->>'reason') AS reason
  FROM totals t;

  -- Stop if a KYC or AML value has no points in the scorecard.
  SELECT kyc_status, aml_risk_level INTO bad FROM tmp_risk WHERE kyc IS NULL OR aml IS NULL LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Scorecard has no points for KYC % / AML %', bad.kyc_status, bad.aml_risk_level;
  END IF;

  -- Stop unless each customer falls in exactly one exposure band and one rating band.
  IF EXISTS (SELECT 1 FROM tmp_risk
             WHERE jsonb_array_length(COALESCE(bands, '[]')) <> 1
                OR jsonb_array_length(COALESCE(ratings, '[]')) <> 1) THEN
    RAISE EXCEPTION 'Every assessable customer must fall in exactly one exposure band and one rating band';
  END IF;

  -- Save a new assessment version; skip if nothing changed.
  INSERT INTO silver.customer_risk_assessment (
    risk_assessment_id, customer_id, assessment_date, assessment_version, risk_score,
    risk_rating, credit_exposure, aml_risk_rating, kyc_risk_rating, assessment_reason,
    assessment_rule, assessment_rule_version, valid_until, recorded_at)
  SELECT 'RA-' || md5(t.customer_id || '|' || p_date || '|' || (COALESCE(v.last_version, 0) + 1)),
         t.customer_id, p_date::timestamp, COALESCE(v.last_version, 0) + 1,
         t.score::numeric(7,4), t.ratings->>0, t.total_credit_exposure,
         t.aml->>'rating', t.kyc->>'rating', t.reason,
         p_rules->>'rule_name', p_rules->>'rule_version', p_date + 1, now()
  FROM tmp_risk t
  LEFT JOIN (
    SELECT a.customer_id, max(a.assessment_version) AS last_version
    FROM silver.customer_risk_assessment a
    WHERE a.assessment_date = p_date::timestamp
    GROUP BY a.customer_id
  ) v ON v.customer_id = t.customer_id
  WHERE NOT EXISTS (
    SELECT 1 FROM silver.customer_risk_assessment a
    WHERE a.customer_id = t.customer_id AND a.assessment_date = p_date::timestamp
      AND a.assessment_version = v.last_version
      AND a.assessment_rule_version = p_rules->>'rule_version'
      AND a.risk_score = t.score::numeric(7,4)
      AND a.risk_rating = t.ratings->>0
      AND a.credit_exposure = t.total_credit_exposure);
END;
$$;

COMMIT;
