-- PostgreSQL 15+
-- Member 2: Customer Identity Matching
-- Step 3 - Apply deterministic entity-resolution rules.
--
-- The rule order matters. A DOB conflict with otherwise strong evidence
-- is sent to manual review before any acceptance rule can merge it.

CREATE OR REPLACE VIEW silver.v_member2_pair_decisions AS
SELECT
    c.*,

    CASE
        -- Supplied Daniel scenario: same name/phone but conflicting DOB.
        WHEN c.dob_conflict
         AND c.name_match
         AND c.phone_match
        THEN 'PENDING_REVIEW'

        -- Strong deterministic agreements.
        WHEN c.dob_match
         AND c.email_match
         AND c.phone_match
        THEN 'ACCEPTED'

        WHEN c.dob_match
         AND c.email_match
        THEN 'ACCEPTED'

        WHEN c.dob_match
         AND c.phone_match
        THEN 'ACCEPTED'

        WHEN c.dob_match
         AND c.name_match
         AND c.address_match
        THEN 'ACCEPTED'

        ELSE 'NO_MATCH'
    END AS pair_decision,

    CASE
        WHEN c.dob_conflict
         AND c.name_match
         AND c.phone_match
        THEN 0.7000

        WHEN c.dob_match
         AND c.email_match
         AND c.phone_match
        THEN 0.9900

        WHEN c.dob_match
         AND c.email_match
        THEN 0.9700

        WHEN c.dob_match
         AND c.phone_match
        THEN 0.9700

        WHEN c.dob_match
         AND c.name_match
         AND c.address_match
        THEN 0.9200

        ELSE 0.0000
    END::decimal(5,4) AS pair_confidence_score,

    CASE
        WHEN c.dob_conflict
         AND c.name_match
         AND c.phone_match
        THEN 'DOB_CONFLICT_NAME_PHONE_MATCH'

        WHEN c.dob_match
         AND c.email_match
         AND c.phone_match
        THEN 'DOB_EMAIL_PHONE_EXACT'

        WHEN c.dob_match
         AND c.email_match
        THEN 'DOB_EMAIL_EXACT'

        WHEN c.dob_match
         AND c.phone_match
        THEN 'DOB_PHONE_EXACT'

        WHEN c.dob_match
         AND c.name_match
         AND c.address_match
        THEN 'DOB_NAME_ADDRESS_EXACT'

        ELSE 'NO_MATCH_RULE'
    END AS pair_match_rule

FROM silver.v_member2_match_candidates c;


-- Inspection: only records that require action.
SELECT
    source_a,
    source_ref_a,
    source_b,
    source_ref_b,
    pair_decision,
    pair_confidence_score,
    pair_match_rule
FROM silver.v_member2_pair_decisions
WHERE pair_decision <> 'NO_MATCH'
ORDER BY source_ref_a, source_ref_b;
