-- Step 3: calculate per-customer financial totals for one reporting date.
-- Install: run this file once. Run: SELECT * FROM gold.customer_financials(DATE '2026-09-15');
-- Read-only: returns one row per customer and writes nothing. Used by steps 4 and 5.
BEGIN;

CREATE OR REPLACE FUNCTION gold.customer_financials(p_date date)
RETURNS TABLE (
  customer_id varchar(50),
  total_account_balance numeric, total_outstanding_loans numeric,
  total_overdraft_balance numeric, total_debt numeric,
  banking_credit_exposure numeric, lending_credit_exposure numeric,
  total_credit_exposure numeric,
  total_income numeric, total_cost numeric, net_profit numeric,
  financial_data_status text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  -- Stop if step 1 has not run for this date, or if it left OPEN issues (e.g. a loan with no
  -- matched customer). A missing product would silently understate that customer's totals.
  IF NOT EXISTS (SELECT 1 FROM silver.data_lineage_record WHERE lineage_id = 'FIN-' || p_date) THEN
    RAISE EXCEPTION 'Run CALL silver.load_financials(%) first', p_date;
  END IF;
  IF EXISTS (SELECT 1 FROM silver.data_quality_issue
             WHERE validation_run_id = 'FIN-' || p_date AND issue_status = 'OPEN') THEN
    RAISE EXCEPTION 'Financial load for % has open issues; see silver.data_quality_issue', p_date;
  END IF;

  -- Stop if any account or loan is not dated exactly p_date. Silver keeps only the current
  -- amounts, so older or newer amounts cannot stand in for the reporting date.
  IF EXISTS (SELECT 1 FROM silver.banking_account WHERE as_of_date <> p_date)
     OR EXISTS (SELECT 1 FROM silver.loan WHERE as_of_date <> p_date) THEN
    RAISE EXCEPTION 'Silver accounts/loans are not all dated %; run silver.load_financials for that date', p_date;
  END IF;

  RETURN QUERY
  -- Build a product list p with one row per account or loan (UNION ALL). Columns that do not
  -- apply to a product type are 0. Overdraft is the negative part of an account balance.
  -- Accounts and loans are never joined to each other, so nothing is double counted.
  WITH p AS (
    SELECT a.customer_id, a.current_balance AS balance, 0 AS outstanding,
           greatest(-a.current_balance, 0) AS overdraft,
           a.credit_exposure AS bank_exp, 0 AS lend_exp, a.daily_income AS income, a.daily_cost AS cost
    FROM silver.banking_account a
    UNION ALL
    SELECT l.customer_id, 0, l.outstanding_balance, 0,
           0, l.credit_exposure, l.daily_income, l.daily_cost
    FROM silver.loan l
  ), g AS (
    -- Group the product list into one row per customer (LEFT JOIN keeps customers with no
    -- products). Balances are summed, with 0 for customers without products.
    -- Exposure, income and cost are summed only when every product value is known:
    -- count(x) skips NULLs and count(p.customer_id) counts products; otherwise the result is NULL.
    SELECT c.customer_id,
           COALESCE(sum(p.balance), 0) AS balance,
           COALESCE(sum(p.outstanding), 0) AS outstanding,
           COALESCE(sum(p.overdraft), 0) AS overdraft,
           CASE WHEN count(p.bank_exp) = count(p.customer_id) THEN COALESCE(sum(p.bank_exp), 0) END AS bank_exp,
           CASE WHEN count(p.lend_exp) = count(p.customer_id) THEN COALESCE(sum(p.lend_exp), 0) END AS lend_exp,
           CASE WHEN count(p.income) = count(p.customer_id) THEN COALESCE(sum(p.income), 0) END AS income,
           CASE WHEN count(p.cost) = count(p.customer_id) THEN COALESCE(sum(p.cost), 0) END AS cost
    FROM silver.customer_master c
    LEFT JOIN p ON p.customer_id = c.customer_id
    GROUP BY c.customer_id
  )
  -- Derive the final metrics: debt = loans + overdraft, total exposure = banking + lending,
  -- net profit = income - cost. Status is PARTIAL when any optional metric is unknown.
  SELECT g.customer_id, g.balance, g.outstanding, g.overdraft, g.outstanding + g.overdraft,
         g.bank_exp, g.lend_exp, g.bank_exp + g.lend_exp,
         g.income, g.cost, g.income - g.cost,
         CASE WHEN g.bank_exp IS NULL OR g.lend_exp IS NULL OR g.income IS NULL OR g.cost IS NULL
              THEN 'PARTIAL' ELSE 'COMPLETE' END
  FROM g;
END;
$$;

COMMIT;
