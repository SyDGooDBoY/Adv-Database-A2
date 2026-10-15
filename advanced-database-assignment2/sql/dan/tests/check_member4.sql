-- Member4 end-to-end checks. Read-only: safe to run on the shared database after the full run.
-- Checks the latest published snapshot date. Every row should show PASS.
WITH d AS (
  SELECT max(snapshot_date) AS snapshot_date FROM gold.fact_customer_snapshot
),
-- Snapshot rows for the checked date.
s AS (
  SELECT f.* FROM gold.fact_customer_snapshot f JOIN d USING (snapshot_date)
),
-- Silver totals per customer, summed separately for accounts and loans.
acc AS (
  SELECT customer_id, sum(current_balance) AS balance
  FROM silver.banking_account a JOIN d ON a.as_of_date = d.snapshot_date
  GROUP BY customer_id
),
lns AS (
  SELECT customer_id, sum(outstanding_balance) AS outstanding
  FROM silver.loan l JOIN d ON l.as_of_date = d.snapshot_date
  GROUP BY customer_id
),
checks AS (
  -- 1. A snapshot was published.
  SELECT 1 AS check_no, 'Snapshot published' AS check_name,
         (SELECT count(*) FROM s) > 0 AS passed,
         (SELECT count(*) FROM s) || ' customers' AS detail
  UNION ALL
  -- 2. One row per customer per date.
  SELECT 2, 'One row per customer per date',
         NOT EXISTS (SELECT customer_id FROM s GROUP BY customer_id HAVING count(*) > 1),
         'duplicates: ' || (SELECT count(*) FROM (SELECT customer_id FROM s GROUP BY customer_id HAVING count(*) > 1) x)
  UNION ALL
  -- 3. Account balances match Silver (no double counting).
  SELECT 3, 'Account balance matches Silver',
         NOT EXISTS (SELECT 1 FROM s LEFT JOIN acc USING (customer_id)
                     WHERE s.total_account_balance <> COALESCE(acc.balance, 0)),
         'total ' || (SELECT sum(total_account_balance) FROM s)
  UNION ALL
  -- 4. Loan balances match Silver (no double counting).
  SELECT 4, 'Outstanding loans match Silver',
         NOT EXISTS (SELECT 1 FROM s LEFT JOIN lns USING (customer_id)
                     WHERE s.total_outstanding_loans <> COALESCE(lns.outstanding, 0)),
         'total ' || (SELECT sum(total_outstanding_loans) FROM s)
  UNION ALL
  -- 5. Debt = outstanding loans + overdraft.
  SELECT 5, 'Debt = loans + overdraft',
         NOT EXISTS (SELECT 1 FROM s WHERE total_debt <> total_outstanding_loans + total_overdraft_balance),
         'total debt ' || (SELECT sum(total_debt) FROM s)
  UNION ALL
  -- 6. Missing values stay NULL and are flagged PARTIAL, never shown as 0.
  SELECT 6, 'Unknown values are NULL and PARTIAL',
         NOT EXISTS (SELECT 1 FROM s
                     WHERE (financial_data_status = 'PARTIAL')
                         = (total_credit_exposure IS NOT NULL AND net_profit IS NOT NULL)),
         'partial: ' || (SELECT count(*) FROM s WHERE financial_data_status = 'PARTIAL')
  UNION ALL
  -- 7. At most one current dimension version per customer.
  SELECT 7, 'One current DIM_CUSTOMER version',
         NOT EXISTS (SELECT customer_id FROM gold.dim_customer WHERE current_flag
                     GROUP BY customer_id HAVING count(*) > 1),
         (SELECT count(*) FROM gold.dim_customer) || ' versions'
  UNION ALL
  -- 8. Each snapshot row uses the dimension version valid on the snapshot date.
  SELECT 8, 'Snapshot uses version valid on date',
         NOT EXISTS (SELECT 1 FROM s JOIN gold.dim_customer dc ON dc.customer_key = s.customer_key
                     WHERE dc.customer_id <> s.customer_id
                        OR dc.effective_from >= s.snapshot_date + 1
                        OR dc.effective_to < s.snapshot_date + 1),
         'checked ' || (SELECT count(*) FROM s)
  UNION ALL
  -- 9. Every customer has a risk assessment.
  SELECT 9, 'Every customer risk-assessed',
         NOT EXISTS (SELECT 1 FROM s WHERE risk_assessment_id IS NULL),
         (SELECT string_agg(risk_rating || '=' || n, ', ' ORDER BY risk_rating)
          FROM (SELECT risk_rating, count(*) n FROM s GROUP BY risk_rating) x)
  UNION ALL
  -- 10. Data issues were logged and none are left open.
  SELECT 10, 'No open data quality issues',
         NOT EXISTS (SELECT 1 FROM silver.data_quality_issue q, d
                     WHERE q.validation_run_id = 'FIN-' || d.snapshot_date AND q.issue_status = 'OPEN'),
         (SELECT count(*) FROM silver.data_quality_issue q, d
          WHERE q.validation_run_id = 'FIN-' || d.snapshot_date) || ' issues logged'
  UNION ALL
  -- 11. Report views agree with the snapshot table.
  SELECT 11, 'Report views match snapshot',
         (SELECT total_debt FROM gold.v_portfolio_health JOIN d USING (snapshot_date))
           = (SELECT sum(total_debt) FROM s)
         AND (SELECT sum(customer_count) FROM gold.v_portfolio_risk_distribution JOIN d USING (snapshot_date))
           = (SELECT count(*) FROM s),
         'checked health + distribution'
)
SELECT (SELECT snapshot_date FROM d) AS snapshot_date, check_no, check_name,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result, detail
FROM checks
ORDER BY check_no;
