-- PostgreSQL 15+
-- Member 2: Customer Identity Matching
-- Step 2 - Standardise matching fields and generate cross-system candidates.
--
-- The original retained Silver source values are not overwritten.
-- Standardisation exists only in a matching-input view.

CREATE OR REPLACE VIEW silver.v_member2_matching_input AS
WITH base AS (
    SELECT
        scr.source_customer_record_id,
        scr.source_system_id,
        scr.batch_id,
        scr.source_customer_reference,
        scr.source_record_version,
        scr.bronze_record_reference,
        scr.source_full_name,
        scr.source_date_of_birth,
        scr.source_email_address,
        scr.source_phone_number,
        scr.source_address,
        scr.source_last_updated_at,
        scr.valid_from,
        scr.valid_to,
        scr.is_current_version,

        REGEXP_REPLACE(
            COALESCE(scr.source_phone_number, ''),
            '[^0-9]',
            '',
            'g'
        ) AS phone_digits

    FROM silver.source_customer_record scr
    WHERE scr.is_current_version = TRUE
),
normalised AS (
    SELECT
        b.*,

        -- Handles the supplied Lending format "WONG, ALICE".
        NULLIF(
            CASE
                WHEN POSITION(',' IN COALESCE(b.source_full_name, '')) > 0
                THEN REGEXP_REPLACE(
                    UPPER(
                        TRIM(SPLIT_PART(b.source_full_name, ',', 2))
                        || ' ' ||
                        TRIM(SPLIT_PART(b.source_full_name, ',', 1))
                    ),
                    '[[:space:]]+',
                    ' ',
                    'g'
                )
                ELSE REGEXP_REPLACE(
                    UPPER(TRIM(COALESCE(b.source_full_name, ''))),
                    '[[:space:]]+',
                    ' ',
                    'g'
                )
            END,
            ''
        ) AS norm_name,

        b.source_date_of_birth AS norm_dob,

        NULLIF(
            LOWER(TRIM(COALESCE(b.source_email_address, ''))),
            ''
        ) AS norm_email,

        -- 0412... and +61 412... are reduced to the same local digits.
        NULLIF(
            CASE
                WHEN b.phone_digits ~ '^61[0-9]{9}$'
                    THEN SUBSTRING(b.phone_digits FROM 3)
                WHEN b.phone_digits ~ '^0[0-9]{9}$'
                    THEN SUBSTRING(b.phone_digits FROM 2)
                ELSE b.phone_digits
            END,
            ''
        ) AS norm_phone,

        NULLIF(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    UPPER(TRIM(COALESCE(b.source_address, ''))),
                    '[^A-Z0-9 ]',
                    '',
                    'g'
                ),
                '[[:space:]]+',
                ' ',
                'g'
            ),
            ''
        ) AS norm_address

    FROM base b
)
SELECT *
FROM normalised;


CREATE OR REPLACE VIEW silver.v_member2_match_candidates AS
SELECT
    a.source_customer_record_id AS record_a_id,
    a.source_system_id          AS source_a,
    a.source_customer_reference AS source_ref_a,

    b.source_customer_record_id AS record_b_id,
    b.source_system_id          AS source_b,
    b.source_customer_reference AS source_ref_b,

    a.norm_name    AS name_a,
    b.norm_name    AS name_b,
    a.norm_dob     AS dob_a,
    b.norm_dob     AS dob_b,
    a.norm_email   AS email_a,
    b.norm_email   AS email_b,
    a.norm_phone   AS phone_a,
    b.norm_phone   AS phone_b,
    a.norm_address AS address_a,
    b.norm_address AS address_b,

    (
        a.norm_name IS NOT NULL
        AND b.norm_name IS NOT NULL
        AND a.norm_name = b.norm_name
    ) AS name_match,

    (
        a.norm_dob IS NOT NULL
        AND b.norm_dob IS NOT NULL
        AND a.norm_dob = b.norm_dob
    ) AS dob_match,

    (
        a.norm_dob IS NOT NULL
        AND b.norm_dob IS NOT NULL
        AND a.norm_dob <> b.norm_dob
    ) AS dob_conflict,

    (
        a.norm_email IS NOT NULL
        AND b.norm_email IS NOT NULL
        AND a.norm_email = b.norm_email
    ) AS email_match,

    (
        a.norm_phone IS NOT NULL
        AND b.norm_phone IS NOT NULL
        AND a.norm_phone = b.norm_phone
    ) AS phone_match,

    (
        a.norm_address IS NOT NULL
        AND b.norm_address IS NOT NULL
        AND a.norm_address = b.norm_address
    ) AS address_match,

    (
        (CASE WHEN a.norm_name IS NOT NULL
                    AND b.norm_name IS NOT NULL
                    AND a.norm_name = b.norm_name
               THEN 1 ELSE 0 END)
        +
        (CASE WHEN a.norm_dob IS NOT NULL
                    AND b.norm_dob IS NOT NULL
                    AND a.norm_dob = b.norm_dob
               THEN 1 ELSE 0 END)
        +
        (CASE WHEN a.norm_email IS NOT NULL
                    AND b.norm_email IS NOT NULL
                    AND a.norm_email = b.norm_email
               THEN 1 ELSE 0 END)
        +
        (CASE WHEN a.norm_phone IS NOT NULL
                    AND b.norm_phone IS NOT NULL
                    AND a.norm_phone = b.norm_phone
               THEN 1 ELSE 0 END)
        +
        (CASE WHEN a.norm_address IS NOT NULL
                    AND b.norm_address IS NOT NULL
                    AND a.norm_address = b.norm_address
               THEN 1 ELSE 0 END)
    ) AS matching_field_count

FROM silver.v_member2_matching_input a
JOIN silver.v_member2_matching_input b
  ON a.source_customer_record_id < b.source_customer_record_id
 AND a.source_system_id <> b.source_system_id

WHERE
       (
           a.norm_name IS NOT NULL
           AND b.norm_name IS NOT NULL
           AND a.norm_name = b.norm_name
       )
    OR (
           a.norm_dob IS NOT NULL
           AND b.norm_dob IS NOT NULL
           AND a.norm_dob = b.norm_dob
       )
    OR (
           a.norm_email IS NOT NULL
           AND b.norm_email IS NOT NULL
           AND a.norm_email = b.norm_email
       )
    OR (
           a.norm_phone IS NOT NULL
           AND b.norm_phone IS NOT NULL
           AND a.norm_phone = b.norm_phone
       )
    OR (
           a.norm_address IS NOT NULL
           AND b.norm_address IS NOT NULL
           AND a.norm_address = b.norm_address
       );


-- Inspection
SELECT
    source_a,
    source_ref_a,
    source_b,
    source_ref_b,
    name_match,
    dob_match,
    dob_conflict,
    email_match,
    phone_match,
    address_match,
    matching_field_count
FROM silver.v_member2_match_candidates
ORDER BY source_ref_a, source_ref_b;
