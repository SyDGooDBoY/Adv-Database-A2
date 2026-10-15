-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 4: Assign one customer ID to accepted source records

BEGIN;

-- Close matches that belong to an old source record version
UPDATE silver.customer_source_match m
SET
    effective_to = CURRENT_TIMESTAMP,
    is_current_match = FALSE
FROM silver.source_customer_record scr
WHERE m.source_customer_record_id = scr.source_customer_record_id
  AND m.is_current_match = TRUE
  AND scr.is_current_version = FALSE;

-- Rebuild current decisions for current source records
UPDATE silver.customer_source_match m
SET
    effective_to = CURRENT_TIMESTAMP,
    is_current_match = FALSE
WHERE m.is_current_match = TRUE
  AND EXISTS (
      SELECT 1
      FROM silver.v_member2_matching_input i
      WHERE i.source_customer_record_id = m.source_customer_record_id
  );

-- 1. Find records that need manual review
-- Source priority is used only to choose which side is held back
-- CRM = 1, AML/KYC = 2, Lending = 3
DROP TABLE IF EXISTS tmp_member2_pending;

CREATE TEMP TABLE tmp_member2_pending AS
WITH pending_candidates AS (
    SELECT
        CASE
            WHEN
                CASE source_a
                    WHEN 'CRM' THEN 1
                    WHEN 'AMLKYC' THEN 2
                    WHEN 'LEND' THEN 3
                    ELSE 9
                END
                >
                CASE source_b
                    WHEN 'CRM' THEN 1
                    WHEN 'AMLKYC' THEN 2
                    WHEN 'LEND' THEN 3
                    ELSE 9
                END
            THEN record_a_id
            ELSE record_b_id
        END AS source_customer_record_id,

        pair_confidence_score,
        pair_match_rule

    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'PENDING_REVIEW'
)

SELECT
    source_customer_record_id,
    MAX(pair_confidence_score) AS match_confidence_score,
    MIN(pair_match_rule) AS match_rule
FROM pending_candidates
GROUP BY source_customer_record_id;

-- 2. Build a simple group for accepted records
-- Each accepted pair links two source records
-- For the supplied three-source prototype, all sources are directly compared, so MIN(record_id) gives the same group key to matching rows
-- Single source customers simply keep their own record ID as the key
DROP TABLE IF EXISTS tmp_member2_assignment;

CREATE TEMP TABLE tmp_member2_assignment AS
WITH eligible_records AS (
    SELECT i.*
    FROM silver.v_member2_matching_input i
    WHERE NOT EXISTS (
        SELECT 1
        FROM tmp_member2_pending p
        WHERE p.source_customer_record_id = i.source_customer_record_id
    )
),

group_options AS (
    -- Every record can use itself as a group key
    SELECT
        source_customer_record_id AS record_id,
        source_customer_record_id AS group_key
    FROM eligible_records

    UNION ALL

    -- Accepted link: A can also use B as a group key
    SELECT
        d.record_a_id,
        d.record_b_id
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'

    UNION ALL

    -- Accepted link: B can also use A as a group key
    SELECT
        d.record_b_id,
        d.record_a_id
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'
),

customer_groups AS (
    SELECT
        record_id,
        MIN(group_key) AS group_key
    FROM group_options
    GROUP BY record_id
)

SELECT
    e.source_customer_record_id,

    -- Stable enterprise customer ID for the group
    'CUST-' ||
    UPPER(
        SUBSTRING(
            MD5(g.group_key)
            FROM 1 FOR 12
        )
    ) AS customer_id

FROM eligible_records e
JOIN customer_groups g
  ON e.source_customer_record_id = g.record_id;

-- 3. Create customer_master shells
-- Module 3 will  choose the authoritative name, DOB, email, phone and address. ON CONFLICT prevents this script from replacing Module 3's existing golden customer values
INSERT INTO silver.customer_master (
    customer_id,
    customer_full_name,
    date_of_birth,
    email_address,
    phone_number,
    residential_address,
    suburb_city,
    state_region,
    postcode,
    country_code,
    customer_status,
    customer_since_date,
    created_at,
    last_updated_at
)

SELECT DISTINCT
    customer_id,
    'PENDING SURVIVORSHIP'::varchar(150),
    NULL::date,
    NULL::varchar(150),
    NULL::varchar(50),
    NULL::varchar(255),
    NULL::varchar(100),
    NULL::varchar(100),
    NULL::varchar(20),
    NULL::varchar(3),
    'PENDING_SURVIVORSHIP'::varchar(30),
    NULL::date,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP

FROM tmp_member2_assignment

ON CONFLICT (customer_id) DO NOTHING;

-- 4. Collect the best matching evidence for each accepted record
DROP TABLE IF EXISTS tmp_member2_evidence;

CREATE TEMP TABLE tmp_member2_evidence AS
WITH evidence AS (
    SELECT
        record_a_id AS source_customer_record_id,
        pair_confidence_score,
        pair_match_rule
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'

    UNION ALL

    SELECT
        record_b_id,
        pair_confidence_score,
        pair_match_rule
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
)

SELECT
    source_customer_record_id,
    MAX(pair_confidence_score) AS match_confidence_score,
    MIN(pair_match_rule) AS match_rule
FROM evidence
GROUP BY source_customer_record_id;

-- 5. Save accepted and pending review decisions
INSERT INTO silver.customer_source_match (
    match_id,
    source_customer_record_id,
    customer_id,
    reviewed_by_user_id,
    match_status,
    match_confidence_score,
    match_rule,
    manual_review_flag,
    effective_from,
    effective_to,
    is_current_match,
    matched_at
)

-- Accepted records
SELECT
    'MATCH-' ||
    UPPER(
        SUBSTRING(
            MD5(
                a.source_customer_record_id
                || '|ACCEPTED|'
                || a.customer_id
            )
            FROM 1 FOR 12
        )
    ),

    a.source_customer_record_id,
    a.customer_id,
    NULL::varchar(50),
    'ACCEPTED',

    COALESCE(
        e.match_confidence_score,
        1.0000::decimal(5,4)
    ),

    COALESCE(
        e.match_rule,
        'NEW_CUSTOMER_SINGLE_SOURCE'
    ),

    FALSE,
    CURRENT_TIMESTAMP,
    NULL::timestamp,
    TRUE,
    CURRENT_TIMESTAMP

FROM tmp_member2_assignment a
LEFT JOIN tmp_member2_evidence e
  ON a.source_customer_record_id = e.source_customer_record_id

UNION ALL

-- Records that need manual review
SELECT
    'MATCH-' ||
    UPPER(
        SUBSTRING(
            MD5(
                p.source_customer_record_id
                || '|PENDING_REVIEW|'
                || p.match_rule
            )
            FROM 1 FOR 12
        )
    ),

    p.source_customer_record_id,
    NULL::varchar(50),
    NULL::varchar(50),
    'PENDING_REVIEW',
    p.match_confidence_score,
    p.match_rule,
    TRUE,
    CURRENT_TIMESTAMP,
    NULL::timestamp,
    TRUE,
    CURRENT_TIMESTAMP

FROM tmp_member2_pending p

-- Rerunning the script updates the same decision instead of duplicating it
ON CONFLICT (match_id) DO UPDATE
SET
    customer_id = EXCLUDED.customer_id,
    match_status = EXCLUDED.match_status,
    match_confidence_score = EXCLUDED.match_confidence_score,
    match_rule = EXCLUDED.match_rule,
    manual_review_flag = EXCLUDED.manual_review_flag,
    effective_to = NULL,
    is_current_match = TRUE,
    matched_at = CURRENT_TIMESTAMP;

COMMIT;

-- check
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
ORDER BY scr.source_system_id, scr.source_customer_reference;