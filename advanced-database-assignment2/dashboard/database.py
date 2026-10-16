"""PostgreSQL connection and read-only dashboard queries."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.engine import URL


BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")


@dataclass(frozen=True)
class DatabaseConfig:
    host: str
    port: int
    database: str
    user: str
    password: str
    sslmode: str = "prefer"


def database_config_from_env() -> DatabaseConfig:
    """Build connection settings without exposing credentials in source code."""
    required = {
        "DB_HOST": os.getenv("DB_HOST"),
        "DB_NAME": os.getenv("DB_NAME"),
        "DB_USER": os.getenv("DB_USER"),
        "DB_PASSWORD": os.getenv("DB_PASSWORD"),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing database settings: "
            + ", ".join(missing)
            + ". Copy .env.example to .env and enter the underlying PostgreSQL details."
        )
    return DatabaseConfig(
        host=required["DB_HOST"] or "",
        port=int(os.getenv("DB_PORT", "5432")),
        database=required["DB_NAME"] or "",
        user=required["DB_USER"] or "",
        password=required["DB_PASSWORD"] or "",
        sslmode=os.getenv("DB_SSLMODE", "prefer"),
    )


def build_engine(config: DatabaseConfig | None = None) -> Engine:
    """Create a SQLAlchemy engine for the project PostgreSQL database."""
    settings = config or database_config_from_env()
    url = URL.create(
        drivername="postgresql+psycopg",
        username=settings.user,
        password=settings.password,
        host=settings.host,
        port=settings.port,
        database=settings.database,
        query={"sslmode": settings.sslmode},
    )
    return create_engine(url, pool_pre_ping=True, pool_recycle=300)


PORTFOLIO_HEALTH_SQL = """
SELECT snapshot_date, customer_count, partial_customer_count,
       unassessed_customer_count, total_account_balance,
       total_outstanding_loans, total_overdraft_balance, total_debt,
       total_credit_exposure, total_net_profit
FROM gold.v_portfolio_health
ORDER BY snapshot_date
"""

RISK_DISTRIBUTION_SQL = """
SELECT snapshot_date, risk_rating, customer_count, total_debt
FROM gold.v_portfolio_risk_distribution
ORDER BY snapshot_date, risk_rating
"""

CUSTOMER_PROFILE_SQL = """
SELECT snapshot_date, customer_id, customer_full_name, customer_status,
       total_account_balance, total_outstanding_loans,
       total_overdraft_balance, total_debt, total_credit_exposure,
       net_profit, financial_data_status, kyc_status, aml_risk_level,
       risk_score, risk_rating, kyc_risk_rating, aml_risk_rating,
       assessment_reason, assessment_rule, assessment_rule_version
FROM gold.v_customer_risk_profile
ORDER BY snapshot_date, customer_id
"""

# This evaluates KYC/AML from the current Member 5 Silver records for each Gold
# snapshot date. It remains useful when the original snapshot was created before
# Member 5 was loaded and therefore stored UNKNOWN statuses.
COMPLIANCE_STATUS_SQL = """
WITH reporting_dates AS (
  SELECT DISTINCT snapshot_date
  FROM gold.fact_customer_snapshot
)
SELECT reporting_date.snapshot_date,
       compliance.kyc_status,
       compliance.aml_risk_level,
       count(*)::integer AS customer_count
FROM reporting_dates reporting_date
CROSS JOIN LATERAL gold.customer_compliance(reporting_date.snapshot_date) compliance
GROUP BY reporting_date.snapshot_date,
         compliance.kyc_status,
         compliance.aml_risk_level
ORDER BY reporting_date.snapshot_date,
         compliance.kyc_status,
         compliance.aml_risk_level
"""

COMPLIANCE_EXCEPTIONS_SQL = """
SELECT exception_fact_id, exception_source_type, exception_type,
       exception_status, severity, opened_date, resolved_date, as_of_date,
       days_open, customer_id, customer_name, case_reason
FROM gold.vw_kyc_aml_exception_report
ORDER BY as_of_date DESC, severity, days_open DESC
"""


def _read(engine: Engine, query: str) -> pd.DataFrame:
    return pd.read_sql_query(text(query), engine)


def load_dashboard_data(engine: Engine | None = None) -> dict[str, pd.DataFrame]:
    """Load every read-only dataset used by the three dashboard pages."""
    owned_engine = engine is None
    connection = engine or build_engine()
    try:
        return {
            "portfolio_health": _read(connection, PORTFOLIO_HEALTH_SQL),
            "risk_distribution": _read(connection, RISK_DISTRIBUTION_SQL),
            "customer_profile": _read(connection, CUSTOMER_PROFILE_SQL),
            "compliance_status": _read(connection, COMPLIANCE_STATUS_SQL),
            "compliance_exceptions": _read(connection, COMPLIANCE_EXCEPTIONS_SQL),
        }
    finally:
        if owned_engine:
            connection.dispose()
