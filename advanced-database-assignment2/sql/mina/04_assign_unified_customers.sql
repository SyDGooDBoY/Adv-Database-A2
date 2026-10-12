-- Module 2: Customer indentity matching
-- Step 4: Assign enterprise customer IDs and save match decisions

BEGIN;

-- ------------------------------------------------
-- 1. Close match decisions for source versions that are no longer current
--    This handles updates/deletes produced by the CDC process
-- ------------------------------------------------
UPDATE silver.customer_source_match m
SET
    effective_to = COALESCE(m.effective_to, CURRENT_TIMESTAMP),
    is_current_match = FALSE
FROM silver.source_customer_record scr
WHERE m.source_customer_record_id = scr.source_customer_record_id
  AND m.is_current_match = TRUE
  AND scr.is_current_version = FALSE;


-- ------------------------------------------------
-- 2. Identify records that must wait for manual review
--
-- For a conflicting pair, CRM is preferred as the temporary anchor,
-- then AML/KYC, then Lending. This is ONLY for identity review and
-- is not an attribute survivorship rule
-- ------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_review_pending;

CREATE TEMP TABLE tmp_member2_review_pending AS
WITH accepted_records AS (
    SELECT record_a_id AS record_id
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
    UNION
    SELECT record_b_id
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
),
review_candidates AS (
    SELECT
        CASE
            WHEN
                CASE source_a WHEN 'CRM' THEN 1 WHEN 'AMLKYC' THEN 2
                              WHEN 'LEND' THEN 3 ELSE 9 END
                <=
                CASE source_b WHEN 'CRM' THEN 1 WHEN 'AMLKYC' THEN 2
                              WHEN 'LEND' THEN 3 ELSE 9 END
            THEN record_b_id
            ELSE record_a_id
        END AS source_customer_record_id,
        pair_confidence_score,
        pair_match_rule
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'PENDING_REVIEW'
)
SELECT DISTINCT ON (r.source_customer_record_id)
    r.source_customer_record_id,
    r.pair_confidence_score,
    r.pair_match_rule
FROM review_candidates r
WHERE NOT EXISTS (
    SELECT 1
    FROM accepted_records a
    WHERE a.record_id = r.source_customer_record_id
)
ORDER BY r.source_customer_record_id, r.pair_confidence_score DESC;


-- ------------------------------------------------
-- 3. Group ACCEPTED source identities into one enterprise customer
--
-- Think of every accepted pair as an edge in a graph
-- The recursive CTE finds all connected source identities
-- MIN(node_key) gives each connected group one stable component root
-- ------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_assignment;

CREATE TEMP TABLE tmp_member2_assignment AS
WITH RECURSIVE
nodes AS (
    SELECT
        i.source_customer_record_id,
        i.source_system_id || '|' || i.source_customer_reference AS node_key
    FROM silver.v_member2_matching_input i
    WHERE NOT EXISTS (
        SELECT 1
        FROM tmp_member2_review_pending p
        WHERE p.source_customer_record_id = i.source_customer_record_id
    )
),
edges AS (
    -- Add both directions so the graph can be traversed either way
    SELECT
        source_a || '|' || source_ref_a AS from_node,
        source_b || '|' || source_ref_b AS to_node
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'

    UNION

    SELECT
        source_b || '|' || source_ref_b,
        source_a || '|' || source_ref_a
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
),
reach(start_node, node_key) AS (
    -- Every node can reach itself.
    SELECT node_key, node_key
    FROM nodes

    UNION

    -- Follow accepted edges until no new connected node is found.
    SELECT r.start_node, e.to_node
    FROM reach r
    JOIN edges e ON e.from_node = r.node_key
    JOIN nodes n ON n.node_key = e.to_node
),
components AS (
    SELECT
        start_node AS node_key,
        MIN(node_key) AS component_root
    FROM reach
    GROUP BY start_node
),
historical_ids AS (
    -- Reuse an existing enterprise ID when rerunning after a new source version
    SELECT DISTINCT
        scr.source_system_id || '|' || scr.source_customer_reference AS node_key,
        m.customer_id
    FROM silver.customer_source_match m
    JOIN silver.source_customer_record scr
      ON scr.source_customer_record_id = m.source_customer_record_id
    WHERE m.match_status = 'ACCEPTED'
      AND m.customer_id IS NOT NULL
),
existing_by_component AS (
    SELECT
        c.component_root,
        MIN(h.customer_id) AS existing_customer_id
    FROM components c
    JOIN historical_ids h ON h.node_key = c.node_key
    GROUP BY c.component_root
)
SELECT
    n.source_customer_record_id,
    COALESCE(
        e.existing_customer_id,
        -- MD5 creates a short deterministic ID from the component root
        'CUST-' || UPPER(SUBSTRING(MD5(c.component_root) FROM 1 FOR 12))
    ) AS customer_id
FROM nodes n
JOIN components c ON c.node_key = n.node_key
LEFT JOIN existing_by_component e
  ON e.component_root = c.component_root;


-- ------------------------------------------------
-- 4. Create only missing CUSTOMER_MASTER shells
--
-- Explicit casts on NULL values avoid PostgreSQL date/text type errors
-- ------------------------------------------------
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
    CURRENT_TIMESTAMP::timestamp,
    CURRENT_TIMESTAMP::timestamp
FROM tmp_member2_assignment
ON CONFLICT (customer_id) DO NOTHING;


-- ------------------------------------------------
-- 5. Close the previous current decision for records being recalculated
--    The same deterministic match_id can then be reactivated on rerun safely
-- ------------------------------------------------
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


-- ------------------------------------------------
-- 6. Build and save the desired decisions
-- ------------------------------------------------
WITH desired_matches AS (
    -- Automatically accepted identities, including single-source customers
    SELECT
        'MATCH-' || UPPER(SUBSTRING(MD5(
            a.source_customer_record_id || '|ACCEPTED|' || a.customer_id
        ) FROM 1 FOR 12)) AS match_id,

        a.source_customer_record_id,
        a.customer_id,
        NULL::varchar(50) AS reviewed_by_user_id,
        'ACCEPTED'::varchar(20) AS match_status,

        -- Use the strongest accepted pair evidence for this record
        COALESCE(ev.pair_confidence_score, 1.0000::decimal(5,4))
            AS match_confidence_score,

        COALESCE(ev.pair_match_rule, 'NEW_CUSTOMER_SINGLE_SOURCE')::varchar(150)
            AS match_rule,

        FALSE AS manual_review_flag,
        CURRENT_TIMESTAMP AS effective_from,
        NULL::timestamp AS effective_to,
        TRUE AS is_current_match,
        CURRENT_TIMESTAMP AS matched_at

    FROM tmp_member2_assignment a

    -- LATERAL lets this subquery use the current row from 'a'
    LEFT JOIN LATERAL (
        SELECT
            d.pair_confidence_score,
            d.pair_match_rule
        FROM silver.v_member2_pair_decisions d
        WHERE d.pair_decision = 'ACCEPTED'
          AND (
              d.record_a_id = a.source_customer_record_id
              OR d.record_b_id = a.source_customer_record_id
          )
        ORDER BY d.pair_confidence_score DESC
        LIMIT 1
    ) ev ON TRUE

    UNION ALL

    -- Uncertain identities remain unassigned until manual review
    SELECT
        'MATCH-' || UPPER(SUBSTRING(MD5(
            p.source_customer_record_id || '|PENDING_REVIEW|' || p.pair_match_rule
        ) FROM 1 FOR 12)),
        p.source_customer_record_id,
        NULL::varchar(50),
        NULL::varchar(50),
        'PENDING_REVIEW'::varchar(20),
        p.pair_confidence_score,
        p.pair_match_rule::varchar(150),
        TRUE,
        CURRENT_TIMESTAMP,
        NULL::timestamp,
        TRUE,
        CURRENT_TIMESTAMP
    FROM tmp_member2_review_pending p
)
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
SELECT *
FROM desired_matches

-- Rerunning updates the same deterministic decision instead of duplicating it
ON CONFLICT (match_id) DO UPDATE
SET
    customer_id            = EXCLUDED.customer_id,
    match_status           = EXCLUDED.match_status,
    match_confidence_score = EXCLUDED.match_confidence_score,
    match_rule             = EXCLUDED.match_rule,
    manual_review_flag     = EXCLUDED.manual_review_flag,
    effective_to           = NULL,
    is_current_match       = TRUE,
    matched_at             = EXCLUDED.matched_at;

COMMIT;


-- Check if current source identity -> enterprise customer decision
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_record_version,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule,
    m.manual_review_flag
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE m.is_current_match = TRUE
ORDER BY scr.source_system_id, scr.source_customer_reference;