-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 3: Apply simple deterministic matching rules

CREATE OR REPLACE VIEW silver.v_member2_pair_decisions AS
SELECT
    c.*,

    -- The conflict rule is checked first
    CASE
        WHEN dob_conflict AND name_match AND phone_match
            THEN 'PENDING_REVIEW'

        WHEN dob_match AND email_match AND phone_match
            THEN 'ACCEPTED'

        WHEN dob_match AND email_match
            THEN 'ACCEPTED'

        WHEN dob_match AND phone_match
            THEN 'ACCEPTED'

        WHEN dob_match AND name_match AND address_match
            THEN 'ACCEPTED'

        ELSE 'NO_MATCH'
    END AS pair_decision,

    CASE
        WHEN dob_conflict AND name_match AND phone_match THEN 0.7000
        WHEN dob_match AND email_match AND phone_match   THEN 0.9900
        WHEN dob_match AND email_match                   THEN 0.9700
        WHEN dob_match AND phone_match                   THEN 0.9700
        WHEN dob_match AND name_match AND address_match  THEN 0.9200
        ELSE 0.0000
    END::decimal(5,4) AS pair_confidence_score,

    -- Save the rule so the decision can be explained later
    CASE
        WHEN dob_conflict AND name_match AND phone_match
            THEN 'DOB_CONFLICT_NAME_PHONE_MATCH'
        WHEN dob_match AND email_match AND phone_match
            THEN 'DOB_EMAIL_PHONE_EXACT'
        WHEN dob_match AND email_match
            THEN 'DOB_EMAIL_EXACT'
        WHEN dob_match AND phone_match
            THEN 'DOB_PHONE_EXACT'
        WHEN dob_match AND name_match AND address_match
            THEN 'DOB_NAME_ADDRESS_EXACT'
        ELSE 'NO_MATCH_RULE'
    END AS pair_match_rule

FROM silver.v_member2_match_candidates c;

-- Show only decisions that need action
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