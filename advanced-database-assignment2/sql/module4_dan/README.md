# Module 4: Customer and Portfolio Analytics

## Purpose

Module 4 turns the trusted customer record and the banking and lending data into daily customer and portfolio reports.

It loads accounts, loans and transactions into Silver, keeps customer history in a dimension, calculates each customer's financial position, assigns a risk rating, and publishes one snapshot row per customer per day.

Module 4 does not decide which source records belong to the same customer or which values are trusted. That is handled by Module 2 and Module 3. It also does not produce the KYC/AML results; it reads them from Module 5.

---

## Architecture

Module 4 operates in the Silver and Gold layers of the Medallion architecture.

```text
Module 1
Bronze ingestion / CDC
Module 2 + Module 3
Unified customer_id + golden customer record
Module 5
KYC / AML results
Module 4
Silver financials → DIM_CUSTOMER → risk assessment → FACT_CUSTOMER_SNAPSHOT
Reporting views → dashboard
```

The module uses the relational model in Silver and a dimensional star schema in Gold: an SCD Type 2 customer dimension and a daily periodic snapshot fact.

---

## Files

### `01_load_silver_financials.sql`

Creates `silver.load_financials(date)`, which loads accounts, loans and transactions from Bronze into Silver.

Main tasks:
- loads only records whose customer has an `ACCEPTED` match
- logs records without an accepted match in `silver.data_quality_issue` (ID prefix `FIN-`)
- can be rerun for the same date without creating duplicates

### `02_load_dim_customer.sql`

Creates `gold.load_dim_customer()`, which keeps customer history in `gold.dim_customer` as SCD Type 2.

```text
Name or status changes
→ close the old version (effective_to, current_flag = false)
→ insert a new current version
```

### `03_customer_financials.sql`

Creates `gold.customer_financials(date)`, which calculates each customer's:

```text
total_account_balance
total_outstanding_loans
total_overdraft_balance
total_debt = loans + overdraft
total_credit_exposure
net_profit
```

Accounts and loans are summed separately and then joined, so nothing is double counted.

### `04_customer_risk_assessment.sql`

Creates:
- `gold.customer_compliance(date)`: reads each customer's KYC status and AML risk level from Module 5's tables
- `silver.assess_customer_risk(date, rules)`: writes `silver.customer_risk_assessment`

The rules are passed in as a JSON weighted scorecard (`demo_scorecard`, version "3"). Each KYC status and AML risk level has its own points, so every combination gets a score without listing combinations one by one:

```text
score = base 20 + KYC points + AML points (+ exposure points), capped at 100

KYC:  VERIFIED 0 | UNKNOWN 15 | EXPIRED 55 | MISSING_DOCUMENT 55
AML:  CLEAR 0 | FALSE_POSITIVE 0 | UNKNOWN 15 | LOW 20 | POTENTIAL_MATCH 40 | MEDIUM 40 | HIGH 70 | CRITICAL 80
Exposure (only when KYC and AML are both UNKNOWN): below 50,000 → 0 | 50,000 or more → 30

Rating: below 50 LOW | 50-74 MEDIUM | 75 or more HIGH
```

Examples: VERIFIED + CLEAR = 20 LOW; VERIFIED + open MEDIUM AML case = 60 MEDIUM; EXPIRED + CLEAR = 75 HIGH; no KYC/AML result with exposure 50,000 or more = 80 HIGH.

The run stops with an error if the JSON is missing a section, if a customer's KYC or AML value has no points, or if a score falls in no rating band (or more than one). Each assessment stores the rule name, version and a reason built from the KYC, AML and exposure parts.

Version "3" replaced the earlier 8-row decision table (version "2"). It gives every current customer exactly the same score, rating and reason, and also covers combinations the decision table did not list (for example EXPIRED + open AML case).

The scores are prototype assumptions, not statistical probabilities. Module 5 should confirm them.

### `05_customer_snapshot.sql`

Creates `gold.publish_snapshot(date, rules)`, which publishes `gold.fact_customer_snapshot`: one row per customer per day.

Rerunning the same date with the same data changes nothing. If the result would change, the run stops unless `p_allow_correction => true` is passed, so a published report is never overwritten silently.

### `06_reporting_views.sql`

Creates the report views used by the dashboard:

```text
gold.v_portfolio_health
gold.v_portfolio_risk_distribution
gold.v_customer_risk_profile
```

### `07_run_reporting_date.sql`

Runs the whole module for two reporting dates, 2026-09-01 and then 2026-09-15, and shows each result:

```text
7.0 Clear Member 4 financial and snapshot data (so the file can be rerun)
7.1 Load DIM_CUSTOMER
7.2 1 Sep: load Silver financials and list data quality issues
7.3 1 Sep: review and acknowledge data quality issues
7.4 1 Sep: customer totals
7.5 1 Sep: risk assessment (weighted scorecard, version "3") and daily snapshot
7.6 15 Sep: load, acknowledge and customer totals
7.7 15 Sep: risk assessment and daily snapshot
7.8 Reports for both dates
7.9 Customers whose rating or debt changed between the dates
```

Dates must run oldest first. Silver keeps only the latest date, so each date's snapshot is published before the next date is loaded. Gold keeps one snapshot per date.

### `test_member4.sql`

Eleven read-only checks. Every row should show `PASS`.

Main test cases:
- **Totals:** balance 63,700, loans 668,200, debt 669,300 for 10 customers.
- **Olivia:** balance −1,100 becomes overdraft 1,100; debt 112,400.
- **LOAN-002:** no accepted customer match, logged as a data quality issue.
- **Risk:** every customer has exactly one rating (LOW 4 / MEDIUM 4 / HIGH 2 with Module 5 data).

The checks run on the latest snapshot date (2026-09-15).
- **History:** the snapshot uses the DIM_CUSTOMER version valid on the reporting date.

---

## Main Outputs

```text
silver.banking_account
silver.loan
silver.account_transaction
silver.customer_risk_assessment
gold.dim_customer
gold.fact_customer_snapshot
gold.v_portfolio_health
gold.v_portfolio_risk_distribution
gold.v_customer_risk_profile
```

The main final output of Module 4 is `gold.fact_customer_snapshot`, which the reporting views and the dashboard read.

---

## Run Order

Run the shared setup, Module 1, Module 2, Module 3 (including `CALL silver.apply_member3_survivorship();`) and Module 5 (including its pipeline calls) first.

Then run:

```text
01_load_silver_financials.sql
02_load_dim_customer.sql
03_customer_financials.sql
04_customer_risk_assessment.sql
05_customer_snapshot.sql
06_reporting_views.sql
07_run_reporting_date.sql
test_member4.sql
```

Files 01–06 only create procedures, functions and views. File 07 loads the data.

Module 5 must run before file 07. Otherwise every customer is assessed as `UNKNOWN` and the result is HIGH 4 / MEDIUM 6.

---

## Module 4 vs Module 5

```text
Module 5:
What is each customer's KYC and AML status?

Module 4:
Given that status and the customer's exposure, what is the risk rating, and how does the portfolio look on each day?
```

---

## Prototype Notes

The risk rules and scores are assumptions created for this prototype and synthetic dataset.

The source data has two financial dates, so the module publishes two snapshots:

| Date | Customers | Total debt | LOW / MEDIUM / HIGH |
|---|---|---|---|
| 2026-09-01 | 9 | 677,400 | 5 / 2 / 2 |
| 2026-09-15 | 10 | 669,300 | 4 / 4 / 2 |

Between the dates, Mia Rivera becomes a new customer and Olivia Brooks moves from LOW to MEDIUM after an AML case rated MEDIUM is opened. With two dates the dashboard shows trend lines.
