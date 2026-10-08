-- PostgreSQL 15+
-- Member 2: Customer Identity Matching
-- Step 4 - Create unified customer identities and retained matching decisions.
--
-- Responsibility boundary:
--   Member 2 decides which source identities belong to the same customer.
--   Member 3 decides which source attribute values survive into the final
--   golden record and maintains attribute history.
--
-- CUSTOMER_MASTER is therefore seeded only with a placeholder row so that
-- CUSTOMER_SOURCE_MATCH can satisfy its foreign key. No final survivorship
-- is performed here.
--
-- Rerunnable:
--   * stable source identities are used for component grouping;
--   * existing enterprise customer IDs are reused where possible;
--   * old source-version matches are closed;
--   * exact reruns do not create duplicate decisions.

BEGIN;

-- ------------------------------------------------------------
-- 1. Close matching decisions for Silver source versions that are
--    no longer current. This handles Member 1 CDC updates/deletes.
-- ------------------------------------------------------------
UPDATE silver.customer_source_match m
SET
    effective_to     = COALESCE(m.effective_to, CURRENT_TIMESTAMP),
    is_current_match = FALSE
FROM silver.source_customer_record scr
WHERE m.source_customer_record_id = scr.source_customer_record_id
  AND m.is_current_match = TRUE
  AND scr.is_current_version = FALSE;


-- ------------------------------------------------------------
-- 2. Identify the uncertain source record to hold for review.
--
-- In the supplied data Daniel has a CRM/Lending DOB conflict.
-- CRM > AMLKYC > LEND is used only as a deterministic review anchor,
-- not as an attribute-survivorship rule. The lower-priority side is
-- held as PENDING_REVIEW.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_review_pending;

CREATE TEMP TABLE tmp_member2_review_pending AS
WITH review_pairs AS (
    SELECT
        d.record_a_id,
        d.source_a,
        d.record_b_id,
        d.source_b,
        d.pair_confidence_score,
        d.pair_match_rule,

        CASE d.source_a
            WHEN 'CRM'    THEN 1
            WHEN 'AMLKYC' THEN 2
            WHEN 'LEND'   THEN 3
            ELSE 9
        END AS priority_a,

        CASE d.source_b
            WHEN 'CRM'    THEN 1
            WHEN 'AMLKYC' THEN 2
            WHEN 'LEND'   THEN 3
            ELSE 9
        END AS priority_b

    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'PENDING_REVIEW'
),
accepted_record_ids AS (
    SELECT record_a_id AS source_customer_record_id
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'

    UNION

    SELECT record_b_id
    FROM silver.v_member2_pair_decisions
    WHERE pair_decision = 'ACCEPTED'
),
pending_candidates AS (
    SELECT
        CASE
            WHEN rp.priority_a <= rp.priority_b
                THEN rp.record_b_id
            ELSE rp.record_a_id
        END AS source_customer_record_id,

        rp.pair_confidence_score,
        rp.pair_match_rule

    FROM review_pairs rp
),
ranked AS (
    SELECT
        pc.*,
        ROW_NUMBER() OVER (
            PARTITION BY pc.source_customer_record_id
            ORDER BY
                pc.pair_confidence_score DESC,
                pc.pair_match_rule
        ) AS rn

    FROM pending_candidates pc
    WHERE NOT EXISTS (
        SELECT 1
        FROM accepted_record_ids ar
        WHERE ar.source_customer_record_id = pc.source_customer_record_id
    )
)
SELECT
    source_customer_record_id,
    pair_confidence_score,
    pair_match_rule
FROM ranked
WHERE rn = 1;


-- ------------------------------------------------------------
-- 3. Build stable source-identity nodes.
--    The node key deliberately excludes source_record_version so a
--    CRM update (e.g. Ethan V1 -> V2) retains the same identity.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_nodes;

CREATE TEMP TABLE tmp_member2_nodes AS
SELECT
    i.*,
    i.source_system_id || '|' || i.source_customer_reference AS node_key
FROM silver.v_member2_matching_input i
WHERE NOT EXISTS (
    SELECT 1
    FROM tmp_member2_review_pending p
    WHERE p.source_customer_record_id = i.source_customer_record_id
);


-- ------------------------------------------------------------
-- 4. Treat ACCEPTED pair decisions as graph edges and find connected
--    components. This correctly groups three-source customers rather
--    than assigning IDs pair-by-pair.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_components;

CREATE TEMP TABLE tmp_member2_components AS
WITH RECURSIVE
edges AS (
    SELECT
        d.source_a || '|' || d.source_ref_a AS from_node,
        d.source_b || '|' || d.source_ref_b AS to_node
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'

    UNION

    SELECT
        d.source_b || '|' || d.source_ref_b,
        d.source_a || '|' || d.source_ref_a
    FROM silver.v_member2_pair_decisions d
    WHERE d.pair_decision = 'ACCEPTED'
),
reach(start_node, node_key) AS (
    SELECT
        n.node_key,
        n.node_key
    FROM tmp_member2_nodes n

    UNION

    SELECT
        r.start_node,
        e.to_node
    FROM reach r
    JOIN edges e
      ON e.from_node = r.node_key
    JOIN tmp_member2_nodes n
      ON n.node_key = e.to_node
)
SELECT
    start_node AS node_key,
    MIN(node_key) AS component_root
FROM reach
GROUP BY start_node;


-- ------------------------------------------------------------
-- 5. Reuse an existing enterprise customer ID when a component has
--    already been matched on an earlier run/version. Otherwise create
--    a deterministic ID from the component root.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_identity_assignment;

CREATE TEMP TABLE tmp_member2_identity_assignment AS
WITH historical_ids AS (
    SELECT DISTINCT
        scr.source_system_id || '|' || scr.source_customer_reference AS node_key,
        m.customer_id
    FROM silver.customer_source_match m
    JOIN silver.source_customer_record scr
      ON scr.source_customer_record_id = m.source_customer_record_id
    WHERE m.customer_id IS NOT NULL
      AND m.match_status = 'ACCEPTED'
),
component_existing AS (
    SELECT
        c.component_root,
        MIN(h.customer_id) AS existing_customer_id
    FROM tmp_member2_components c
    JOIN historical_ids h
      ON h.node_key = c.node_key
    GROUP BY c.component_root
),
assigned AS (
    SELECT
        n.*,
        c.component_root,

        COALESCE(
            ce.existing_customer_id,
            'CUST-' ||
            UPPER(SUBSTRING(MD5(c.component_root) FROM 1 FOR 12))
        ) AS customer_id

    FROM tmp_member2_nodes n
    JOIN tmp_member2_components c
      ON c.node_key = n.node_key
    LEFT JOIN component_existing ce
      ON ce.component_root = c.component_root
)
SELECT
    a.*,
    COUNT(*) OVER (
        PARTITION BY a.component_root
    ) AS identity_group_size
FROM assigned a;


-- ------------------------------------------------------------
-- 6. Seed only missing CUSTOMER_MASTER IDs.
--
-- The model requires customer_full_name and customer_status to be NOT NULL,
-- so neutral placeholders are used. Member 3 owns authoritative attributes
-- and must replace/enrich them through survivorship logic.
-- ------------------------------------------------------------
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
    a.customer_id,
    'PENDING SURVIVORSHIP',
    NULL::date,
    NULL::varchar(150),
    NULL::varchar(50),
    NULL::varchar(255),
    NULL::varchar(100),
    NULL::varchar(100),
    NULL::varchar(20),
    NULL::varchar(3),
    'PENDING_SURVIVORSHIP',
    NULL::date,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM tmp_member2_identity_assignment a

ON CONFLICT (customer_id) DO NOTHING;


-- ------------------------------------------------------------
-- 7. Find the strongest accepted pair-level evidence for each current
--    source record. Single-source customers have no pair evidence.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_best_evidence;

CREATE TEMP TABLE tmp_member2_best_evidence AS
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
),
ranked AS (
    SELECT
        e.*,
        ROW_NUMBER() OVER (
            PARTITION BY e.source_customer_record_id
            ORDER BY
                e.pair_confidence_score DESC,
                e.pair_match_rule
        ) AS rn
    FROM evidence e
)
SELECT
    source_customer_record_id,
    pair_confidence_score,
    pair_match_rule
FROM ranked
WHERE rn = 1;


-- ------------------------------------------------------------
-- 8. Create one desired current matching decision for each current
--    source record: ACCEPTED or PENDING_REVIEW.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS tmp_member2_match_output;

CREATE TEMP TABLE tmp_member2_match_output AS

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
    ) AS match_id,

    a.source_customer_record_id,
    a.customer_id,
    NULL::varchar(50) AS reviewed_by_user_id,
    'ACCEPTED'::varchar(20) AS match_status,

    COALESCE(
        e.pair_confidence_score,
        1.0000::decimal(5,4)
    ) AS match_confidence_score,

    COALESCE(
        e.pair_match_rule,
        'NEW_CUSTOMER_SINGLE_SOURCE'
    )::varchar(150) AS match_rule,

    FALSE AS manual_review_flag,
    CURRENT_TIMESTAMP AS effective_from,
    NULL::timestamp AS effective_to,
    TRUE AS is_current_match,
    CURRENT_TIMESTAMP AS matched_at

FROM tmp_member2_identity_assignment a
LEFT JOIN tmp_member2_best_evidence e
  ON e.source_customer_record_id = a.source_customer_record_id

UNION ALL

SELECT
    'MATCH-' ||
    UPPER(
        SUBSTRING(
            MD5(
                p.source_customer_record_id
                || '|PENDING_REVIEW|'
                || p.pair_match_rule
            )
            FROM 1 FOR 12
        )
    ) AS match_id,

    p.source_customer_record_id,
    NULL::varchar(50) AS customer_id,
    NULL::varchar(50) AS reviewed_by_user_id,
    'PENDING_REVIEW'::varchar(20) AS match_status,
    p.pair_confidence_score,
    p.pair_match_rule::varchar(150),
    TRUE AS manual_review_flag,
    CURRENT_TIMESTAMP AS effective_from,
    NULL::timestamp AS effective_to,
    TRUE AS is_current_match,
    CURRENT_TIMESTAMP AS matched_at

FROM tmp_member2_review_pending p;


-- ------------------------------------------------------------
-- 9. Close a current decision if the desired current decision changed.
-- ------------------------------------------------------------
UPDATE silver.customer_source_match old_match
SET
    effective_to     = COALESCE(old_match.effective_to, CURRENT_TIMESTAMP),
    is_current_match = FALSE
WHERE old_match.is_current_match = TRUE
  AND EXISTS (
      SELECT 1
      FROM tmp_member2_match_output new_match
      WHERE new_match.source_customer_record_id
            = old_match.source_customer_record_id
        AND new_match.match_id <> old_match.match_id
  );


-- ------------------------------------------------------------
-- 10. Insert/update the desired current decisions.
-- ------------------------------------------------------------
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
SELECT
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
FROM tmp_member2_match_output

ON CONFLICT (match_id) DO UPDATE
SET
    customer_id            = EXCLUDED.customer_id,
    match_status           = EXCLUDED.match_status,
    match_confidence_score = EXCLUDED.match_confidence_score,
    match_rule             = EXCLUDED.match_rule,
    manual_review_flag     = EXCLUDED.manual_review_flag,
    effective_to           = NULL,
    is_current_match       = TRUE;


COMMIT;


-- Inspection
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
ORDER BY
    scr.source_system_id,
    scr.source_customer_reference;

