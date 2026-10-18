# Customer Risk Dashboard

This folder contains a Python dashboard made with Streamlit.

The dashboard reads data from PostgreSQL and shows three pages:

1. **Portfolio Overview** – customer totals, balances, loans, debt, exposure and daily net profit.
2. **Risk & Compliance** – risk levels, KYC, AML and high-risk customers.
3. **Customer Risk Profile** – one customer's details, history and risk reasons.

The dashboard never shows document numbers or passwords.

## Main files

| File | What it does |
|---|---|
| `app.py` | Builds the three Streamlit pages. |
| `database.py` | Connects to PostgreSQL and runs the SQL queries. |
| `analytics.py` | Filters dates and prepares data for charts. |
| `demo_data.py` | Provides example data when the database is unavailable. |
| `.env` | Stores the local database login. Do not upload this file. |
| `run_dashboard.ps1` | Starts the dashboard on Windows. |
| `tests/` | Contains the automatic tests. |

## First-time setup

Open PowerShell in this `dashboard` folder.

### 1. Create a Python environment

The environment keeps this project's Python packages separate from other projects.

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

You only need to do this once.

### 2. Create the database settings file

```powershell
Copy-Item .env.example .env
notepad .env
```

For the local Docker setup used by this project, the file normally looks like this:

```text
DB_HOST=localhost
DB_PORT=5432
DB_NAME=postgres
DB_USER=student
DB_PASSWORD=your_password
DB_SSLMODE=prefer

DASHBOARD_USE_DEMO_DATA=false
DASHBOARD_ALLOW_DEMO_FALLBACK=true
```

Important:

- Use `localhost` because the dashboard runs on Windows.
- CloudBeaver uses `postgres` as its host because CloudBeaver runs inside Docker.
- Do not put the CloudBeaver website address or port `8978` in `.env`.
- Do not share or commit the real password.

## Start the dashboard

Run:

```powershell
.\run_dashboard.ps1
```

Then open:

```text
http://localhost:8501
```

To stop the dashboard, return to PowerShell and press `Ctrl+C`.

## Refresh the data

Click **Refresh data** in the left sidebar after changing PostgreSQL data.

The dashboard normally keeps data for 60 seconds before reading it again.

## Run the tests

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

The tests check:

- all three pages can open;
- date filters work;
- changing a date keeps the selected customer when possible;
- portfolio and risk totals are correct;
- KYC and AML counts are correct;
- high-risk customers are sorted by debt.

All tests should show `passed`.

## Use example data

If PostgreSQL is unavailable, open `.env` and set:

```text
DASHBOARD_USE_DEMO_DATA=true
```

Restart the dashboard. The sidebar will say **Synthetic demo data**.

For final assignment screenshots, use the real PostgreSQL data:

```text
DASHBOARD_USE_DEMO_DATA=false
DASHBOARD_ALLOW_DEMO_FALLBACK=false
```

This makes database problems visible instead of silently using example data.

## What the numbers mean

- Portfolio and risk charts use customers in `gold.fact_customer_snapshot`.
- KYC and AML charts use all identified customers from `gold.customer_compliance(date)`.
- On 15 September 2026, KYC/AML includes 13 customers. The financial snapshot includes 10 customers. The other 3 customers have no account or loan for that date.
- If the database has only one report date, the dashboard shows bars instead of a trend line.
- With both 1 September and 15 September loaded, the dashboard shows trend lines.

## Common problems

### The page stays on "Loading dashboard data"

A CloudBeaver transaction may be holding a database lock.

1. Cancel the running query in CloudBeaver.
2. Disconnect and reconnect `PostgreSQL@localhost`.
3. Stop the dashboard with `Ctrl+C`.
4. Start it again with `.\run_dashboard.ps1`.
5. Open a new browser tab and go to `http://localhost:8501`.

### Only 15 September appears

Run `04_update_existing_database_member4_07.sql` in CloudBeaver, then run:

```sql
SELECT snapshot_date, count(*)
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date
ORDER BY snapshot_date;
```

The result should contain:

```text
2026-09-01 | 9
2026-09-15 | 10
```

Click **Refresh data** in the dashboard after the SQL finishes.

### The dashboard shows example data

Check the PostgreSQL details in `.env`. Make sure:

```text
DB_HOST=localhost
DB_PORT=5432
DB_NAME=postgres
```

Also make sure the PostgreSQL Docker container is running.

## Suggested assignment screenshots

Take one screenshot from each page:

1. Portfolio Overview with the KPI cards and trend chart.
2. Risk & Compliance with the risk, KYC and AML charts.
3. Customer Risk Profile with one selected customer and the rating reason table.

Keep the data source and selected date visible in each screenshot.
