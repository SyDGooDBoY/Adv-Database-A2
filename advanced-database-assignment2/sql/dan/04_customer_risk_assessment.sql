-- Step 4: assess each customer's risk from financial totals and Member5's KYC/AML results.
-- Install: run this file once. Run: CALL silver.assess_customer_risk(DATE '2026-09-15', '<rules json>');
-- The rules are passed in as JSON agreed with Member5; no thresholds are built into the code:
-- {"rule_name": "...", "rule_version": "...",
--  "rules": [{"kyc_status": "VERIFIED", "aml_risk_level": "CLEAR",
--             "exposure_min": 0, "exposure_max": 10000,      -- [min, max), max may be null
--             "score": 10, "rating": "LOW",
--             "kyc_risk_rating": "LOW", "aml_risk_rating": "LOW", "reason": "..."}]}
BEGIN;

-- Return each customer's KYC status and AML risk level at the end of p_date,
-- read from the compliance tables that Member5 loads into Silver.
CREATE OR REPLACE FUNCTION gold.customer_compliance(p_date date)
RETURNS TABLE (customer_id varchar(50), kyc_status varchar(30), aml_risk_level varchar(30))
LANGUAGE sql STABLE AS $$
  SELECT c.customer_id,
         -- KYC: the latest verification by the end of the day; EXPIRED if its expiry date
         -- has passed, UNKNOWN if the customer has never been verified.
         COALESCE((SELECT CASE WHEN k.expiry_date < p_date THEN 'EXPIRED' ELSE k.verification_status END
                   FROM silver.kyc_verification_record k
                   WHERE k.customer_id = c.customer_id AND k.verification_date < p_date + 1
                   ORDER BY k.verification_date DESC LIMIT 1), 'UNKNOWN'),
         -- AML: the level of the latest case still open at the end of the day; if there is
         -- none, the latest screening result; if there is neither, UNKNOWN.
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

CREATE OR REPLACE PROCEDURE silver.assess_customer_risk(p_date date, p_rules jsonb)
LANGUAGE plpgsql AS $$
BEGIN
  -- Stop if the rules JSON is missing its name, version or rules array.
  IF p_rules->>'rule_name' IS NULL OR p_rules->>'rule_version' IS NULL
     OR jsonb_typeof(p_rules->'rules') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Rules JSON needs rule_name, rule_version and a rules array';
  END IF;

  -- Stop if any rule lacks a field that is written to the assessment table. jsonb_strip_nulls
  -- removes keys whose value is null, so a field set to null also counts as missing.
  -- exposure_max is not required: a missing or null value means "no upper limit".
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rules->'rules') x
             WHERE NOT jsonb_strip_nulls(x) ?& ARRAY['kyc_status', 'aml_risk_level', 'exposure_min',
                                  'score', 'rating', 'kyc_risk_rating', 'aml_risk_rating', 'reason']) THEN
    RAISE EXCEPTION 'Each rule needs kyc_status, aml_risk_level, exposure_min, score, rating, kyc_risk_rating, aml_risk_rating and reason';
  END IF;

  -- Build a temporary list matching each customer with known exposure to the rules.
  -- First turn the JSON rules into a plain table (one row per rule), then LEFT JOIN on the same
  -- KYC status and AML level with exposure in [min, max). A customer with no match gets a NULL rule.
  DROP TABLE IF EXISTS tmp_risk;
  CREATE TEMP TABLE tmp_risk ON COMMIT DROP AS
  WITH rules AS (
    SELECT x->>'kyc_status' AS kyc_status, x->>'aml_risk_level' AS aml_risk_level,
           (x->>'exposure_min')::numeric AS exposure_min,
           (x->>'exposure_max')::numeric AS exposure_max, x AS rule
    FROM jsonb_array_elements(p_rules->'rules') x
  )
  SELECT f.customer_id, f.total_credit_exposure, r.rule
  FROM gold.customer_financials(p_date) f
  JOIN gold.customer_compliance(p_date) c ON c.customer_id = f.customer_id
  LEFT JOIN rules r
    ON r.kyc_status = c.kyc_status AND r.aml_risk_level = c.aml_risk_level
   AND f.total_credit_exposure >= r.exposure_min
   AND (r.exposure_max IS NULL OR f.total_credit_exposure < r.exposure_max)
  WHERE f.total_credit_exposure IS NOT NULL;

  -- Stop unless every customer matched exactly one rule. A gap (no match) or an overlap
  -- (two matches) is an error in the rules; it is never defaulted to low risk.
  IF EXISTS (SELECT 1 FROM tmp_risk GROUP BY customer_id HAVING count(rule) <> 1) THEN
    RAISE EXCEPTION 'Every assessable customer must match exactly one risk rule';
  END IF;

  -- Insert a new assessment version per customer (last version for this date + 1).
  -- Skip customers whose last version for this date already has the same rule version, score,
  -- rating and exposure, so a rerun adds nothing. Earlier versions are kept as history.
  -- Scores are cast to numeric(7,4), the column's precision, so the comparison matches what is stored.
  INSERT INTO silver.customer_risk_assessment (
    risk_assessment_id, customer_id, assessment_date, assessment_version, risk_score,
    risk_rating, credit_exposure, aml_risk_rating, kyc_risk_rating, assessment_reason,
    assessment_rule, assessment_rule_version, valid_until, recorded_at)
  SELECT 'RA-' || md5(t.customer_id || '|' || p_date || '|' || (COALESCE(v.last_version, 0) + 1)),
         t.customer_id, p_date::timestamp, COALESCE(v.last_version, 0) + 1,
         (t.rule->>'score')::numeric(7,4), t.rule->>'rating', t.total_credit_exposure,
         t.rule->>'aml_risk_rating', t.rule->>'kyc_risk_rating', t.rule->>'reason',
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
      AND a.risk_score = (t.rule->>'score')::numeric(7,4)
      AND a.risk_rating = t.rule->>'rating'
      AND a.credit_exposure = t.total_credit_exposure);
END;
$$;

COMMIT;
