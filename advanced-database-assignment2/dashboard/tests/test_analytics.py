import pandas as pd

from analytics import (
    customer_history,
    filter_date,
    has_multiple_dates,
    latest_customer_row,
    ordered_status_counts,
    portfolio_snapshot,
    reporting_dates,
    top_high_risk_customers,
)
from demo_data import load_demo_data


def test_demo_data_supports_three_dashboard_use_cases():
    data = load_demo_data()
    assert set(data) == {
        "portfolio_health",
        "risk_distribution",
        "customer_profile",
        "compliance_status",
        "compliance_exceptions",
    }
    assert len(reporting_dates(data["portfolio_health"])) == 3
    assert has_multiple_dates(data["portfolio_health"])


def test_portfolio_and_risk_filters_use_selected_date():
    data = load_demo_data()
    selected = reporting_dates(data["portfolio_health"])[-1]
    snapshot = portfolio_snapshot(data["portfolio_health"], selected)
    risk = filter_date(data["risk_distribution"], selected)
    assert snapshot["customer_count"] == 10
    assert int(risk["customer_count"].sum()) == 10


def test_kyc_distribution_preserves_customer_total():
    data = load_demo_data()
    selected = reporting_dates(data["portfolio_health"])[-1]
    distribution = ordered_status_counts(
        data["compliance_status"], selected, "kyc_status"
    )
    assert int(distribution["customer_count"].sum()) == 13
    assert int(distribution["customer_count"].sum()) == 10 + 3
    assert "VERIFIED" in set(distribution["kyc_status"])


def test_high_risk_table_is_filtered_and_debt_ranked():
    data = load_demo_data()
    selected = reporting_dates(data["portfolio_health"])[-1]
    result = top_high_risk_customers(data["customer_profile"], selected)
    assert not result.empty
    assert set(result["risk_rating"]).issubset({"HIGH", "CRITICAL"})
    assert result["total_debt"].is_monotonic_decreasing


def test_customer_history_returns_latest_selected_snapshot():
    data = load_demo_data()
    selected = reporting_dates(data["portfolio_health"])[-1]
    history = customer_history(data["customer_profile"], "CUST-001", selected)
    latest = latest_customer_row(history)
    assert len(history) == 3
    assert pd.Timestamp(latest["snapshot_date"]) == pd.Timestamp(selected)
