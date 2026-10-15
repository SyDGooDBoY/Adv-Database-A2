-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 2: Clean matching fields and create candidate pairs

-- The original source values stay unchanged
-- This view only creates standardised values for matching
CREATE OR REPLACE VIEW silver.v_member2_matching_input AS
WITH cleaned AS (
    SELECT
        scr.*,

        -- Remove spaces, brackets, + signs and other phone formatting
        REGEXP_REPLACE(
            COALESCE(scr.source_phone_number, ''),
            '[^0-9]',
            '',
            'g'
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

    -- Standardise names
    -- Example: "WONG, ALICE" becomes "ALICE WONG".
    NULLIF(
        UPPER(
            TRIM(
                CASE
                    WHEN POSITION(',' IN COALESCE(source_full_name, '')) > 0
                    THEN
                        SPLIT_PART(source_full_name, ',', 2)
                        || ' ' ||
                        SPLIT_PART(source_full_name, ',', 1)
                    ELSE source_full_name
                END
            )
        ),
        ''
    ) AS norm_name,

    source_date_of_birth AS norm_dob,

    -- LOWER(TRIM(email))
    NULLIF(
        LOWER(TRIM(COALESCE(source_email_address, ''))),
        ''
    ) AS norm_email,

    -- Convert Australian 04xx and +61 4xx formats to the same digits
    NULLIF(
        CASE
            WHEN phone_digits ~ '^61[0-9]{9}$'
                THEN SUBSTRING(phone_digits FROM 3)
            WHEN phone_digits ~ '^0[0-9]{9}$'
                THEN SUBSTRING(phone_digits FROM 2)
            ELSE phone_digits
        END,
        ''
    ) AS norm_phone,

    -- Standardise address text
    NULLIF(
        REGEXP_REPLACE(
            UPPER(TRIM(COALESCE(source_address, ''))),
            '[^A-Z0-9 ]',
            '',
            'g'
        ),
        ''
    ) AS norm_address

FROM cleaned;

-- Compare customers only across different source systems
-- a.id < b.id prevents the same pair appearing twice
CREATE OR REPLACE VIEW silver.v_member2_match_candidates AS
SELECT
    a.source_customer_record_id AS record_a_id,
    a.source_system_id AS source_a,
    a.source_customer_reference AS source_ref_a,

    b.source_customer_record_id AS record_b_id,
    b.source_system_id AS source_b,
    b.source_customer_reference AS source_ref_b,

    (a.norm_name IS NOT NULL
     AND b.norm_name IS NOT NULL
     AND a.norm_name = b.norm_name) AS name_match,

    (a.norm_dob IS NOT NULL
     AND b.norm_dob IS NOT NULL
     AND a.norm_dob = b.norm_dob) AS dob_match,

    (a.norm_dob IS NOT NULL
     AND b.norm_dob IS NOT NULL
     AND a.norm_dob <> b.norm_dob) AS dob_conflict,

    (a.norm_email IS NOT NULL
     AND b.norm_email IS NOT NULL
     AND a.norm_email = b.norm_email) AS email_match,

    (a.norm_phone IS NOT NULL
     AND b.norm_phone IS NOT NULL
     AND a.norm_phone = b.norm_phone) AS phone_match,

    (a.norm_address IS NOT NULL
     AND b.norm_address IS NOT NULL
     AND a.norm_address = b.norm_address) AS address_match

FROM silver.v_member2_matching_input a
JOIN silver.v_member2_matching_input b
  ON a.source_customer_record_id < b.source_customer_record_id
 AND a.source_system_id <> b.source_system_id

-- Keep only pairs with at least one matching field
WHERE
       (a.norm_name IS NOT NULL AND a.norm_name = b.norm_name)
    OR (a.norm_dob IS NOT NULL AND a.norm_dob = b.norm_dob)
    OR (a.norm_email IS NOT NULL AND a.norm_email = b.norm_email)
    OR (a.norm_phone IS NOT NULL AND a.norm_phone = b.norm_phone)
    OR (a.norm_address IS NOT NULL AND a.norm_address = b.norm_address);

-- check
SELECT *
FROM silver.v_member2_match_candidates
ORDER BY source_ref_a, source_ref_b;