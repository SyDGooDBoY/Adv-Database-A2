-- Module 2: Customer indentity matching
-- Step 2: Standardise identity fields and create candidate pairs

-- Prepare one standardised row for every CURRENT source customer
CREATE OR REPLACE VIEW silver.v_member2_matching_input AS
WITH cleaned AS (
    SELECT
        scr.*,

        -- Remove spaces, brackets, +, etc. from phone numbers
        REGEXP_REPLACE(
            COALESCE(scr.source_phone_number, ''),
            '[^0-9]', '', 'g'
        ) AS phone_digits

    FROM silver.source_customer_record scr
    WHERE scr.is_current_version = TRUE
)
SELECT
    source_customer_record_id,
    source_system_id,
    source_customer_reference,
    source_record_version,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,

    -- Convert "WONG, ALICE" to "ALICE WONG"; otherwise uppercase/trim
    NULLIF(
        REGEXP_REPLACE(
            UPPER(
                CASE
                    WHEN POSITION(',' IN COALESCE(source_full_name, '')) > 0
                    THEN TRIM(SPLIT_PART(source_full_name, ',', 2))
                         || ' ' ||
                         TRIM(SPLIT_PART(source_full_name, ',', 1))
                    ELSE TRIM(COALESCE(source_full_name, ''))
                END
            ),
            '[[:space:]]+', ' ', 'g'
        ),
        ''
    ) AS norm_name,

    source_date_of_birth AS norm_dob,

    -- Email matching is case insensitive
    NULLIF(LOWER(TRIM(COALESCE(source_email_address, ''))), '') AS norm_email,

    -- Australian 04xx and +61 4xx formats are reduced to the same 9 digits
    NULLIF(
        CASE
            WHEN phone_digits ~ '^61[0-9]{9}$' THEN SUBSTRING(phone_digits FROM 3)
            WHEN phone_digits ~ '^0[0-9]{9}$'  THEN SUBSTRING(phone_digits FROM 2)
            ELSE phone_digits
        END,
        ''
    ) AS norm_phone,

    -- Remove punctuation and repeated spaces from addresses
    NULLIF(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                UPPER(TRIM(COALESCE(source_address, ''))),
                '[^A-Z0-9 ]', '', 'g'
            ),
            '[[:space:]]+', ' ', 'g'
        ),
        ''
    ) AS norm_address

FROM cleaned;


-- Compare current records only across DIFFERENT source systems
-- record_a_id < record_b_id prevents the same pair appearing twice
CREATE OR REPLACE VIEW silver.v_member2_match_candidates AS
WITH pairs AS (
    SELECT
        a.source_customer_record_id AS record_a_id,
        a.source_system_id          AS source_a,
        a.source_customer_reference AS source_ref_a,
        b.source_customer_record_id AS record_b_id,
        b.source_system_id          AS source_b,
        b.source_customer_reference AS source_ref_b,

        a.norm_name IS NOT NULL
            AND b.norm_name IS NOT NULL
            AND a.norm_name = b.norm_name AS name_match,

        a.norm_dob IS NOT NULL
            AND b.norm_dob IS NOT NULL
            AND a.norm_dob = b.norm_dob AS dob_match,

        a.norm_dob <> b.norm_dob
            AND a.norm_dob IS NOT NULL
            AND b.norm_dob IS NOT NULL AS dob_conflict,

        a.norm_email IS NOT NULL
            AND b.norm_email IS NOT NULL
            AND a.norm_email = b.norm_email AS email_match,

        a.norm_phone IS NOT NULL
            AND b.norm_phone IS NOT NULL
            AND a.norm_phone = b.norm_phone AS phone_match,

        a.norm_address IS NOT NULL
            AND b.norm_address IS NOT NULL
            AND a.norm_address = b.norm_address AS address_match

    FROM silver.v_member2_matching_input a
    JOIN silver.v_member2_matching_input b
      ON a.source_customer_record_id < b.source_customer_record_id
     AND a.source_system_id <> b.source_system_id
)
SELECT
    p.*,
    -- Number of agreeing identity fields. Useful for inspection/debugging
    (name_match::int + dob_match::int + email_match::int +
     phone_match::int + address_match::int) AS matching_field_count
FROM pairs p
-- Ignore pairs with no matching evidence at all
WHERE name_match OR dob_match OR email_match OR phone_match OR address_match;


-- Check of candidate evidence
SELECT *
FROM silver.v_member2_match_candidates
ORDER BY source_ref_a, source_ref_b;