"""Small helper functions for tables and charts."""

from __future__ import annotations

from datetime import date
from typing import Iterable

import pandas as pd


RISK_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNASSESSED", "UNKNOWN"]
RISK_COLOURS = {
    "CRITICAL": "#7f1d1d",
    "HIGH": "#dc2626",
    "MEDIUM": "#f59e0b",
    "LOW": "#10b981",
    "UNASSESSED": "#64748b",
    "UNKNOWN": "#94a3b8",
}


def prepare_dates(frame: pd.DataFrame, column: str) -> pd.DataFrame:
    """Make sure one column contains dates."""
    result = frame.copy()
    if column in result.columns:
        result[column] = pd.to_datetime(result[column], errors="coerce").dt.date
    return result


def reporting_dates(portfolio_health: pd.DataFrame) -> list[date]:
    """List the report dates from oldest to newest."""
    frame = prepare_dates(portfolio_health, "snapshot_date")
    if "snapshot_date" not in frame.columns:
        return []
    return sorted(value for value in frame["snapshot_date"].dropna().unique())


def filter_date(
    frame: pd.DataFrame,
    selected_date: date,
    column: str = "snapshot_date",
) -> pd.DataFrame:
    """Keep only rows from the selected date."""
    prepared = prepare_dates(frame, column)
    if column not in prepared.columns:
        return prepared.iloc[0:0]
    return prepared.loc[prepared[column] == selected_date].copy()


def portfolio_snapshot(portfolio_health: pd.DataFrame, selected_date: date) -> pd.Series:
    """Get the portfolio totals for one date."""
    rows = filter_date(portfolio_health, selected_date)
    if rows.empty:
        return pd.Series(dtype="object")
    return rows.iloc[0]


def portfolio_history(
    portfolio_health: pd.DataFrame,
    through_date: date,
) -> pd.DataFrame:
    """Get portfolio data up to the selected date."""
    frame = prepare_dates(portfolio_health, "snapshot_date")
    return frame.loc[frame["snapshot_date"] <= through_date].sort_values("snapshot_date")


def ordered_status_counts(
    frame: pd.DataFrame,
    selected_date: date,
    status_column: str,
) -> pd.DataFrame:
    """Count each KYC or AML status for one date."""
    rows = filter_date(frame, selected_date)
    if rows.empty or status_column not in rows.columns:
        return pd.DataFrame(columns=[status_column, "customer_count"])
    result = (
        rows.groupby(status_column, dropna=False)["customer_count"]
        .sum()
        .reset_index()
    )
    result[status_column] = result[status_column].fillna("UNKNOWN")
    return result.sort_values(["customer_count", status_column], ascending=[False, True])


def top_high_risk_customers(
    customer_profile: pd.DataFrame,
    selected_date: date,
    limit: int = 10,
) -> pd.DataFrame:
    """Show the highest-risk customers with the most debt first."""
    rows = filter_date(customer_profile, selected_date)
    high_risk = rows.loc[rows["risk_rating"].isin(["HIGH", "CRITICAL"])].copy()
    columns = [
        "customer_id",
        "customer_full_name",
        "customer_status",
        "risk_rating",
        "risk_score",
        "total_debt",
        "total_credit_exposure",
        "kyc_status",
        "aml_risk_level",
    ]
    available = [column for column in columns if column in high_risk.columns]
    return high_risk.sort_values("total_debt", ascending=False).head(limit)[available]


def customer_history(
    customer_profile: pd.DataFrame,
    customer_id: str,
    through_date: date,
) -> pd.DataFrame:
    """Get one customer's history up to the selected date."""
    frame = prepare_dates(customer_profile, "snapshot_date")
    return frame.loc[
        (frame["customer_id"] == customer_id)
        & (frame["snapshot_date"] <= through_date)
    ].sort_values("snapshot_date")


def latest_customer_row(history: pd.DataFrame) -> pd.Series:
    """Get the newest row from a customer's history."""
    if history.empty:
        return pd.Series(dtype="object")
    return history.sort_values("snapshot_date").iloc[-1]


def has_multiple_dates(frame: pd.DataFrame, column: str = "snapshot_date") -> bool:
    """Check whether the data has more than one report date."""
    prepared = prepare_dates(frame, column)
    return column in prepared.columns and prepared[column].nunique(dropna=True) > 1


def safe_number(value: object, default: float = 0.0) -> float:
    """Turn a value into a number that a chart can use."""
    if value is None or pd.isna(value):
        return default
    return float(value)


def format_currency(value: object) -> str:
    """Show a number as whole-dollar currency."""
    if value is None or pd.isna(value):
        return "N/A"
    return f"${float(value):,.0f}"


def format_integer(value: object) -> str:
    """Show a count with commas."""
    if value is None or pd.isna(value):
        return "0"
    return f"{int(value):,}"


def existing_columns(frame: pd.DataFrame, columns: Iterable[str]) -> list[str]:
    """Keep only column names that are available."""
    return [column for column in columns if column in frame.columns]
