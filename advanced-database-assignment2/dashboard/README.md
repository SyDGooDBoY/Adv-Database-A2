# Python dashboard

This Streamlit application implements the assignment requirement for at least
three report/dashboard use cases over the synthetic customer data warehouse.

## Implemented pages

| Page / use case | Main visuals | Database contract |
|---|---|---|
| Portfolio Overview | Six KPI cards, debt/exposure trend or single-date bars, balance-versus-loans bars | `gold.v_portfolio_health` |
| Risk & Compliance | Risk donut, debt by risk, KYC and AML distributions, top-ten high-risk customers, compliance exceptions | `gold.v_portfolio_risk_distribution`, `gold.v_customer_risk_profile`, `gold.customer_compliance(date)`, `gold.vw_kyc_aml_exception_report` |
| Customer Risk Profile | Customer selector, identity/risk cards, financial history or single-date bars, rating-reason table | `gold.v_customer_risk_profile` |

Every page has a reporting-date filter and a data-cutoff line showing the
PARTIAL and unassessed customer counts. If only one snapshot date exists, the
application deliberately uses bar charts instead of misleading trend lines.
No document number or other direct identity credential is queried or displayed.

## 1. Install

Python 3.11 or 3.12 is recommended. From this folder in PowerShell:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## 2. Configure PostgreSQL

CloudBeaver is the database UI; the Python app connects to the same underlying
PostgreSQL database. It does not connect to the CloudBeaver web URL.

```powershell
Copy-Item .env.example .env
```

Edit `.env` and enter the PostgreSQL host, port, database, username and password.
The `.env` file is ignored by Git. The database account needs read access to the
Gold reporting views and the referenced Silver/Gold functions and tables.

For UI development without database access, set:

```text
DASHBOARD_USE_DEMO_DATA=true
```

Demo mode is clearly labelled in the sidebar and uses deterministic synthetic
data over three dates. For assignment screenshots, use the PostgreSQL warehouse
unless you explicitly state that the screenshot is a UI mock-up.

## 3. Run

```powershell
.\run_dashboard.ps1
```

Or run directly:

```powershell
.\.venv\Scripts\python.exe -m streamlit run app.py
```

Streamlit normally opens `http://localhost:8501`.

## 4. Test

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

The automated tests check the reporting-date filters, portfolio/risk totals,
KYC distribution, high-risk ranking and customer history behavior.

## Suggested report evidence

Capture one screenshot of each page with the data-source label visible:

1. Portfolio Overview: KPI cards plus balance/loan comparison.
2. Risk & Compliance: risk distribution, KYC/AML charts and high-risk table.
3. Customer Risk Profile: selected customer cards, financial chart and the
   explainable rating-reason table.

In the written findings, note the selected reporting date, whether the warehouse
contains one or multiple snapshot dates, the number of PARTIAL/unassessed
customers, the largest risk/debt concentration, and any open KYC/AML exceptions.
