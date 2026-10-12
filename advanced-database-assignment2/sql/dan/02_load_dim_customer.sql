-- Step 2: maintain the customer history dimension (SCD Type 2) from Member3's golden records.
-- Install: run this file once. Run: CALL gold.load_dim_customer();
-- Each name/status change closes the old version and opens a new one, so reports can use the
-- version that was valid on any date.
BEGIN;

-- Surrogate key generator: every new dimension version gets the next customer_key.
CREATE SEQUENCE IF NOT EXISTS gold.dim_customer_key_seq AS bigint;

-- Guarantee at most one current version (current_flag = true) per customer.
CREATE UNIQUE INDEX IF NOT EXISTS dim_customer_one_current
  ON gold.dim_customer (customer_id) WHERE current_flag;

CREATE OR REPLACE PROCEDURE gold.load_dim_customer()
LANGUAGE plpgsql AS $$
BEGIN
  -- Keep the sequence ahead of existing keys. If rows were inserted with manual keys,
  -- move the sequence to the current maximum so nextval cannot produce a duplicate.
  PERFORM setval('gold.dim_customer_key_seq', max(customer_key))
  FROM gold.dim_customer
  HAVING max(customer_key) >= (SELECT last_value FROM gold.dim_customer_key_seq);

  -- Stop if a customer's name or status changed but Member3's last_updated_at is not later
  -- than the current version's start. The new version would otherwise start before the old one.
  IF EXISTS (
    SELECT 1 FROM gold.dim_customer d
    JOIN silver.customer_master c ON c.customer_id = d.customer_id
    WHERE d.current_flag
      AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status)
      AND c.last_updated_at <= d.effective_from
  ) THEN
    RAISE EXCEPTION 'Customer name/status changed without a later last_updated_at';
  END IF;

  -- Close the current version of every customer whose name or status changed
  -- (including a return to the placeholder status). It ends at Member3's update time.
  UPDATE gold.dim_customer d
  SET effective_to = c.last_updated_at, current_flag = false
  FROM silver.customer_master c
  WHERE c.customer_id = d.customer_id AND d.current_flag
    AND (c.customer_full_name, c.customer_status) IS DISTINCT FROM (d.customer_full_name, d.customer_status);

  -- Open a new current version for reportable customers (named, not a placeholder) that have
  -- none: new customers and those closed above. Unchanged customers still have a current
  -- version, so a rerun inserts nothing.
  INSERT INTO gold.dim_customer (
    customer_key, customer_id, customer_full_name, customer_status,
    effective_from, effective_to, current_flag)
  SELECT nextval('gold.dim_customer_key_seq'), c.customer_id, c.customer_full_name,
         c.customer_status, c.last_updated_at, NULL, true
  FROM silver.customer_master c
  WHERE c.customer_status <> 'PENDING_SURVIVORSHIP'
    AND nullif(btrim(c.customer_full_name), '') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM gold.dim_customer d
                    WHERE d.customer_id = c.customer_id AND d.current_flag)
  ORDER BY c.customer_id;
END;
$$;

COMMIT;
