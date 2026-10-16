"""Pure data-selection and formatting helpers used by the dashboard."""

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
    """Return a copy with a normalized date column."""
    result = frame.copy()
    if column in result.columns:
        result[column] = pd.to_datetime(result[column], errors="coerce").dt.date
    return result


def reporting_dates(portfolio_health: pd.DataFrame) -> list[date]:
    """Return sorted reporting dates available to all three pages."""
    frame = prepare_dates(portfolio_health, "snapshot_date")
    if "snapshot_date" not in frame.columns:
        return []
    return sorted(value for value in frame["snapshot_date"].dropna().unique())


def filter_date(
    frame: pd.DataFrame,
    selected_date: date,
    column: str = "snapshot_date",
) -> pd.DataFrame:
    """Return rows for one reporting date."""
    prepared = prepare_dates(frame, column)
    if column not in prepared.columns:
        return prepared.iloc[0:0]
    return prepared.loc[prepared[column] == selected_date].copy()


def portfolio_snapshot(portfolio_health: pd.DataFrame, selected_date: date) -> pd.Series:
    """Return the single portfolio-health row for a date."""
    rows = filter_date(portfolio_health, selected_date)
    if rows.empty:
        return pd.Series(dtype="object")
    return rows.iloc[0]


def portfolio_history(
    portfolio_health: pd.DataFrame,
    through_date: date,
) -> pd.DataFrame:
    """Return portfolio history up to and including a selected date."""
    frame = prepare_dates(portfolio_health, "snapshot_date")
    return frame.loc[frame["snapshot_date"] <= through_date].sort_values("snapshot_date")


def ordered_status_counts(
    frame: pd.DataFrame,
    selected_date: date,
    status_column: str,
) -> pd.DataFrame:
    """Aggregate compliance statuses for a selected date."""
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
    """Return high/critical-risk customers ranked by total debt."""
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
    """Return one customer's risk history through a selected date."""
    frame = prepare_dates(customer_profile, "snapshot_date")
    return frame.loc[
        (frame["customer_id"] == customer_id)
        & (frame["snapshot_date"] <= through_date)
    ].sort_values("snapshot_date")


def latest_customer_row(history: pd.DataFrame) -> pd.Series:
    """Return the latest row from a prepared customer history."""
    if history.empty:
        return pd.Series(dtype="object")
    return history.sort_values("snapshot_date").iloc[-1]


def has_multiple_dates(frame: pd.DataFrame, column: str = "snapshot_date") -> bool:
    """Whether a frame contains more than one usable reporting date."""
    prepared = prepare_dates(frame, column)
    return column in prepared.columns and prepared[column].nunique(dropna=True) > 1


def safe_number(value: object, default: float = 0.0) -> float:
    """Convert nullable database values to a display-safe float."""
    if value is None or pd.isna(value):
        return default
    return float(value)


def format_currency(value: object) -> str:
    """Format a nullable amount without implying cents-level accuracy."""
    if value is None or pd.isna(value):
        return "N/A"
    return f"${float(value):,.0f}"


def format_integer(value: object) -> str:
    """Format a nullable count."""
    if value is None or pd.isna(value):
        return "0"
    return f"{int(value):,}"


def existing_columns(frame: pd.DataFrame, columns: Iterable[str]) -> list[str]:
    """Return requested columns that exist in a frame."""
    return [column for column in columns if column in frame.columns]
