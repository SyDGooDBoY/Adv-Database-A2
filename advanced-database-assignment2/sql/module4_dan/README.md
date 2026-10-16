# Member4 – Customer Analytics

PostgreSQL 15+. Run after the shared setup and the Member1, Member2 and Member3 scripts.

## Run order

1. `01_load_silver_financials.sql`
2. `02_load_dim_customer.sql`
3. `03_customer_financials.sql`
4. `04_customer_risk_assessment.sql`
5. `05_customer_snapshot.sql`
6. `06_reporting_views.sql`
7. `07_run_reporting_date.sql`

Files 01–06 only create the procedures, functions and views. File 07 runs them for 2026-09-15 and loads the data.

## What the scripts do

`01` loads accounts, loans and transactions from Bronze into Silver. Only records with an ACCEPTED customer match are loaded; the rest are logged as data quality issues.

`02` keeps customer history in `gold.dim_customer`. A name or status change closes the old version and adds a new one.

`03` calculates each customer's balance, loans, overdraft, debt, exposure and profit. Accounts and loans are summed separately, so nothing is double counted.

`04` gives each customer a risk rating from their exposure and Member5's KYC/AML results, using rules passed in as JSON.

`05` publishes one snapshot row per customer per day in `gold.fact_customer_snapshot`. Rerunning the same date changes nothing.

`06` creates the report views: `v_portfolio_health`, `v_portfolio_risk_distribution` and `v_customer_risk_profile`.

`07` runs steps 01–06 for one date and shows each result. It uses demo risk rules until Member5's rules JSON is agreed.

## Rules JSON

Thresholds are agreed with Member5. Each customer must match exactly one rule.

```json
{"rule_name": "...", "rule_version": "1",
 "rules": [{"kyc_status": "VERIFIED", "aml_risk_level": "CLEAR",
            "exposure_min": 0, "exposure_max": 10000,
            "score": 10, "rating": "LOW",
            "kyc_risk_rating": "LOW", "aml_risk_rating": "LOW", "reason": "..."}]}
```

## Test

After the full run, execute `tests/check_member4.sql`. It only reads data. Every row should show `PASS`.
