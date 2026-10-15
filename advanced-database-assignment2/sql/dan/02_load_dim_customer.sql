-- Step 2: Keep customer history in DIM_CUSTOMER (SCD Type 2).
-- Run: CALL gold.load_dim_customer();
BEGIN;

-- Generate customer_key for each new version.
CREATE SEQUENCE IF NOT EXISTS gold.dim_customer_key_seq AS bigint;

-- Allow only one current version per customer.
CREATE UNIQUE INDEX IF NOT EXISTS dim_customer_one_current
  ON gold.dim_customer (customer_id) WHERE current_flag;

-- Update the customer dimension from silver.customer_master.
CREATE OR REPLACE PROCEDURE gold.load_dim_customer()
LANGUAGE plpgsql AS $$
BEGIN
  -- Move the key sequence past any existing key.
  PERFORM setval('gold.dim_customer_key_seq', max(customer_key))
  FROM gold.dim_customer
  HAVING max(customer_key) >= (SELECT last_value FROM gold.dim_customer_key_seq);

  -- Stop if a change has no later update time.
  IF EXISTS (
    SELECT 1 FROM gold.dim_customer d
    JOIN silver.customer_master c ON c.customer_id = d.customer_id
    WHERE d.current_flag
      AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status)
      AND c.last_updated_at <= d.effective_from
  ) THEN
    RAISE EXCEPTION 'Customer name/status changed without a later last_updated_at';
  END IF;

  -- Close the current version when name or status changed.
  UPDATE gold.dim_customer d
  SET effective_to = c.last_updated_at, current_flag = false
  FROM silver.customer_master c
  WHERE c.customer_id = d.customer_id AND d.current_flag
    AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status);

  -- Open a new current version for new or changed customers.
  INSERT INTO gold.dim_customer (
    customer_key, customer_id, customer_full_name, customer_status,
    effective_from, effective_to, current_flag)
  -- A brand-new customer starts from its earliest matched source record, so past dates are covered.
  SELECT nextval('gold.dim_customer_key_seq'), c.customer_id, c.customer_full_name, c.customer_status,
         CASE WHEN EXISTS (SELECT 1 FROM gold.dim_customer d WHERE d.customer_id = c.customer_id)
              THEN c.last_updated_at
              ELSE least(c.last_updated_at, s.first_seen) END,
         NULL, true
  FROM silver.customer_master c
  LEFT JOIN (
    SELECT m.customer_id, min(r.source_last_updated_at) AS first_seen
    FROM silver.customer_source_match m
    JOIN silver.source_customer_record r ON r.source_customer_record_id = m.source_customer_record_id
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
    GROUP BY m.customer_id
  ) s ON s.customer_id = c.customer_id
  WHERE c.customer_status <> 'PENDING_SURVIVORSHIP'
    AND nullif(btrim(c.customer_full_name), '') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM gold.dim_customer d
                    WHERE d.customer_id = c.customer_id AND d.current_flag)
  ORDER BY c.customer_id;
END;
$$;

COMMIT;
