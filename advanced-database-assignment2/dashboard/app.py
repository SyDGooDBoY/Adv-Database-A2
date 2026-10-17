"""Streamlit dashboard for the Advanced Database Assignment 2 warehouse."""

from __future__ import annotations

import os

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

from analytics import (
    RISK_COLOURS,
    customer_history,
    existing_columns,
    filter_date,
    format_currency,
    format_integer,
    has_multiple_dates,
    latest_customer_row,
    ordered_status_counts,
    portfolio_history,
    portfolio_snapshot,
    reporting_dates,
    safe_number,
    top_high_risk_customers,
)
from database import load_dashboard_data
from demo_data import load_demo_data


st.set_page_config(
    page_title="Unified Customer Risk Dashboard",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
    menu_items={
        "Get help": None,
        "Report a Bug": None,
        "About": None,
    },
)

st.markdown(
    """
    <style>
      .stApp { background: #f7f9fc; }
      /* Hide Streamlit's top-right Deploy control and overflow menu. */
      [data-testid="stDeployButton"],
      [data-testid="stMainMenu"],
      #MainMenu {
        display: none !important;
      }
      [data-testid="stMetric"] {
        background: white;
        border: 1px solid #e5eaf1;
        border-radius: 14px;
        padding: 14px 16px;
        box-shadow: 0 6px 18px rgba(15, 23, 42, 0.05);
      }
      [data-testid="stMetricLabel"] { color: #526076; }
      h1, h2, h3 { color: #10223e; }
      .block-container { padding-top: 1.5rem; padding-bottom: 3rem; }
      .data-note {
        color: #5d6b82;
        font-size: 0.9rem;
        margin-top: -0.5rem;
        margin-bottom: 1rem;
      }
    </style>
    """,
    unsafe_allow_html=True,
)


def _as_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@st.cache_data(ttl=60, show_spinner="Loading dashboard data...")
def load_app_data() -> tuple[dict[str, pd.DataFrame], str, str | None]:
    """Load PostgreSQL data, with an explicitly labelled demo fallback."""
    if _as_bool("DASHBOARD_USE_DEMO_DATA", False):
        return load_demo_data(), "Synthetic demo data", None
    try:
        return load_dashboard_data(), "PostgreSQL warehouse", None
    except Exception as exc:  # surfaced to the user with no credentials included
        if _as_bool("DASHBOARD_ALLOW_DEMO_FALLBACK", True):
            return load_demo_data(), "Synthetic demo data (fallback)", str(exc)
        raise


def standard_layout(figure: go.Figure, height: int = 390) -> go.Figure:
    figure.update_layout(
        height=height,
        margin=dict(l=20, r=20, t=55, b=20),
        paper_bgcolor="white",
        plot_bgcolor="white",
        font=dict(color="#25324a"),
        legend_title_text="",
        hovermode="x unified",
    )
    figure.update_xaxes(gridcolor="#edf1f6")
    figure.update_yaxes(gridcolor="#edf1f6")
    return figure


def page_header(
    title: str,
    subtitle: str,
    data: dict[str, pd.DataFrame],
    key: str,
):
    st.title(title)
    st.caption(subtitle)
    dates = reporting_dates(data["portfolio_health"])
    if not dates:
        st.error("No reporting dates were found in gold.v_portfolio_health.")
        st.stop()
    selected = st.selectbox(
        "Reporting date",
        options=dates,
        index=len(dates) - 1,
        format_func=lambda value: value.strftime("%d %b %Y"),
        key=f"date_{key}",
    )
    snapshot = portfolio_snapshot(data["portfolio_health"], selected)
    partial = format_integer(snapshot.get("partial_customer_count", 0))
    unassessed = format_integer(snapshot.get("unassessed_customer_count", 0))
    st.markdown(
        f'<div class="data-note">Data as at <b>{selected:%d %B %Y}</b> · '
        f'PARTIAL customers: <b>{partial}</b> · '
        f'Unassessed customers: <b>{unassessed}</b></div>',
        unsafe_allow_html=True,
    )
    return selected, snapshot


def render_portfolio(data: dict[str, pd.DataFrame]) -> None:
    selected, snapshot = page_header(
        "Portfolio Overview",
        "Enterprise portfolio position, exposure and profitability.",
        data,
        "portfolio",
    )

    metrics = [
        ("Customers", format_integer(snapshot.get("customer_count"))),
        ("Total balance", format_currency(snapshot.get("total_account_balance"))),
        ("Total loans", format_currency(snapshot.get("total_outstanding_loans"))),
        ("Total debt", format_currency(snapshot.get("total_debt"))),
        ("Credit exposure", format_currency(snapshot.get("total_credit_exposure"))),
        ("Daily net profit", format_currency(snapshot.get("total_net_profit"))),
    ]
    for start in range(0, len(metrics), 3):
        columns = st.columns(3)
        for column, (label, value) in zip(columns, metrics[start : start + 3]):
            column.metric(label, value)

    history = portfolio_history(data["portfolio_health"], selected)
    left, right = st.columns(2)
    with left:
        if has_multiple_dates(history):
            figure = go.Figure()
            figure.add_trace(
                go.Scatter(
                    x=history["snapshot_date"],
                    y=history["total_debt"],
                    name="Total debt",
                    mode="lines+markers",
                    line=dict(color="#2563eb", width=3),
                )
            )
            figure.add_trace(
                go.Scatter(
                    x=history["snapshot_date"],
                    y=history["total_credit_exposure"],
                    name="Credit exposure",
                    mode="lines+markers",
                    line=dict(color="#f59e0b", width=3),
                )
            )
            figure.update_layout(title="Debt and exposure trend")
        else:
            figure = go.Figure(
                go.Bar(
                    x=["Total debt", "Credit exposure"],
                    y=[
                        safe_number(snapshot.get("total_debt")),
                        safe_number(snapshot.get("total_credit_exposure")),
                    ],
                    marker_color=["#2563eb", "#f59e0b"],
                )
            )
            figure.update_layout(title="Debt and exposure (single reporting date)")
        st.plotly_chart(standard_layout(figure), width="stretch")

    with right:
        comparison = pd.DataFrame(
            {
                "Measure": ["Account balance", "Outstanding loans"],
                "Amount": [
                    safe_number(snapshot.get("total_account_balance")),
                    safe_number(snapshot.get("total_outstanding_loans")),
                ],
            }
        )
        figure = px.bar(
            comparison,
            x="Measure",
            y="Amount",
            color="Measure",
            color_discrete_sequence=["#0f766e", "#7c3aed"],
            title="Balance versus loans",
        )
        figure.update_layout(showlegend=False)
        st.plotly_chart(standard_layout(figure), width="stretch")

    if len(reporting_dates(data["portfolio_health"])) == 1:
        st.info(
            "Only one reporting date is loaded, so the trend visual is shown as a bar chart. "
            "Load additional snapshot dates to enable a meaningful time series."
        )


def render_risk(data: dict[str, pd.DataFrame]) -> None:
    selected, snapshot = page_header(
        "Risk & Compliance",
        "Risk concentration, KYC/AML status and the customers requiring attention.",
        data,
        "risk",
    )
    risk = filter_date(data["risk_distribution"], selected)
    if risk.empty:
        st.warning("No risk distribution exists for this reporting date.")
        return

    left, right = st.columns(2)
    with left:
        figure = px.pie(
            risk,
            names="risk_rating",
            values="customer_count",
            hole=0.58,
            color="risk_rating",
            color_discrete_map=RISK_COLOURS,
            title="Customers by risk rating",
        )
        figure.update_traces(textposition="inside", textinfo="percent+label")
        st.plotly_chart(standard_layout(figure), width="stretch")
    with right:
        figure = px.bar(
            risk,
            x="risk_rating",
            y="total_debt",
            color="risk_rating",
            color_discrete_map=RISK_COLOURS,
            title="Debt by risk rating",
            category_orders={"risk_rating": list(RISK_COLOURS)},
            labels={"risk_rating": "Risk rating", "total_debt": "Total debt"},
        )
        figure.update_layout(showlegend=False)
        st.plotly_chart(standard_layout(figure), width="stretch")

    kyc = ordered_status_counts(data["compliance_status"], selected, "kyc_status")
    aml = ordered_status_counts(data["compliance_status"], selected, "aml_risk_level")
    compliance_customers = int(kyc["customer_count"].sum()) if not kyc.empty else 0
    snapshot_customers = int(safe_number(snapshot.get("customer_count")))
    customers_without_financial_products = max(
        compliance_customers - snapshot_customers,
        0,
    )
    st.info(
        "Population scope: KYC/AML charts include all "
        f"{compliance_customers:,} identified customers returned by "
        "gold.customer_compliance(date). Portfolio KPIs and risk charts include "
        f"the {snapshot_customers:,} customers with an account or loan in the daily "
        f"snapshot. Therefore, {customers_without_financial_products:,} identified "
        "customers have no account or loan for this reporting date and are excluded "
        "from the financial snapshot."
    )
    left, right = st.columns(2)
    with left:
        figure = px.bar(
            kyc,
            x="kyc_status",
            y="customer_count",
            color="kyc_status",
            title="KYC status distribution",
            color_discrete_sequence=px.colors.qualitative.Safe,
            labels={"kyc_status": "KYC status", "customer_count": "Customers"},
        )
        figure.update_layout(showlegend=False)
        st.plotly_chart(standard_layout(figure), width="stretch")
    with right:
        figure = px.bar(
            aml,
            x="aml_risk_level",
            y="customer_count",
            color="aml_risk_level",
            title="AML level distribution",
            color_discrete_sequence=px.colors.qualitative.Set2,
            labels={"aml_risk_level": "AML level", "customer_count": "Customers"},
        )
        figure.update_layout(showlegend=False)
        st.plotly_chart(standard_layout(figure), width="stretch")

    st.subheader("Top 10 high-risk customers by debt")
    high_risk = top_high_risk_customers(data["customer_profile"], selected)
    if high_risk.empty:
        st.success("No HIGH or CRITICAL customers exist for this reporting date.")
    else:
        st.dataframe(
            high_risk,
            width="stretch",
            hide_index=True,
            column_config={
                "customer_id": "Customer ID",
                "customer_full_name": "Customer name",
                "customer_status": "Status",
                "risk_rating": "Risk rating",
                "risk_score": st.column_config.NumberColumn("Risk score", format="%.1f"),
                "total_debt": st.column_config.NumberColumn("Total debt", format="$%.0f"),
                "total_credit_exposure": st.column_config.NumberColumn(
                    "Credit exposure", format="$%.0f"
                ),
                "kyc_status": "KYC status",
                "aml_risk_level": "AML level",
            },
        )

    exceptions = data["compliance_exceptions"].copy()
    if not exceptions.empty:
        st.subheader("Compliance exception monitor")
        exception_cutoff = pd.to_datetime(exceptions["as_of_date"], errors="coerce").max()
        if not pd.isna(exception_cutoff):
            st.caption(f"Compliance data as at {exception_cutoff:%d %B %Y}")
        open_mask = exceptions["exception_status"].isin(["OPEN", "IN_REVIEW"])
        severe_mask = exceptions["severity"].isin(["HIGH", "CRITICAL"])
        e1, e2, e3 = st.columns(3)
        e1.metric("Total exceptions", format_integer(len(exceptions)))
        e2.metric("Open / in review", format_integer(open_mask.sum()))
        e3.metric("High / critical", format_integer(severe_mask.sum()))
        display_columns = existing_columns(
            exceptions,
            [
                "customer_name",
                "exception_source_type",
                "exception_type",
                "exception_status",
                "severity",
                "days_open",
                "case_reason",
            ],
        )
        st.dataframe(
            exceptions.loc[:, display_columns],
            width="stretch",
            hide_index=True,
        )


def render_customer(data: dict[str, pd.DataFrame]) -> None:
    selected, _ = page_header(
        "Customer Risk Profile",
        "Customer-level financial history, current risk rating and explainable reasons.",
        data,
        "customer",
    )
    profile = data["customer_profile"]
    current = filter_date(profile, selected)
    if current.empty:
        st.warning("No customer profiles exist for this reporting date.")
        return

    labels = {
        row.customer_id: f"{row.customer_full_name} ({row.customer_id})"
        for row in current[["customer_id", "customer_full_name"]]
        .drop_duplicates()
        .itertuples(index=False)
    }
    selected_customer = st.selectbox(
        "Customer",
        options=sorted(labels),
        format_func=lambda customer_id: labels[customer_id],
    )
    history = customer_history(profile, selected_customer, selected)
    latest = latest_customer_row(history)

    cards = st.columns([2, 1, 1, 1])
    cards[0].metric("Customer name", latest.get("customer_full_name", "N/A"))
    cards[1].metric("Customer status", latest.get("customer_status", "N/A"))
    cards[2].metric("Current rating", latest.get("risk_rating", "UNASSESSED"))
    risk_score = latest.get("risk_score")
    cards[3].metric(
        "Risk score",
        "N/A" if risk_score is None or pd.isna(risk_score) else f"{float(risk_score):.1f}",
    )

    st.subheader("Balance, loans and debt")
    if has_multiple_dates(history):
        figure = go.Figure()
        for column, label, colour in [
            ("total_account_balance", "Account balance", "#0f766e"),
            ("total_outstanding_loans", "Outstanding loans", "#7c3aed"),
            ("total_debt", "Total debt", "#dc2626"),
        ]:
            figure.add_trace(
                go.Scatter(
                    x=history["snapshot_date"],
                    y=history[column],
                    name=label,
                    mode="lines+markers",
                    line=dict(color=colour, width=3),
                )
            )
        figure.update_layout(title="Customer financial history")
    else:
        figure = go.Figure(
            go.Bar(
                x=["Account balance", "Outstanding loans", "Total debt"],
                y=[
                    safe_number(latest.get("total_account_balance")),
                    safe_number(latest.get("total_outstanding_loans")),
                    safe_number(latest.get("total_debt")),
                ],
                marker_color=["#0f766e", "#7c3aed", "#dc2626"],
            )
        )
        figure.update_layout(title="Customer financial position (single reporting date)")
    st.plotly_chart(standard_layout(figure, height=420), width="stretch")

    st.subheader("Daily rating and reason")
    table_columns = existing_columns(
        history,
        [
            "snapshot_date",
            "risk_rating",
            "risk_score",
            "kyc_status",
            "aml_risk_level",
            "assessment_reason",
            "assessment_rule",
            "assessment_rule_version",
        ],
    )
    st.dataframe(
        history.loc[:, table_columns].sort_values("snapshot_date", ascending=False),
        width="stretch",
        hide_index=True,
    )
    st.caption(
        "The dashboard displays customer name and enterprise customer ID only. "
        "It does not query or display document numbers or other direct identity credentials."
    )


def main() -> None:
    try:
        data, source, fallback_error = load_app_data()
    except Exception as exc:
        st.error("The dashboard could not load its PostgreSQL datasets.")
        st.exception(exc)
        st.stop()

    with st.sidebar:
        st.header("Unified Customer DW")
        page = st.radio(
            "Dashboard page",
            ["Portfolio Overview", "Risk & Compliance", "Customer Risk Profile"],
        )
        st.divider()
        st.caption(f"Data source: {source}")
        if st.button("Refresh data", width="stretch"):
            st.cache_data.clear()
            st.rerun()
        st.caption("PostgreSQL 15+ · Bronze / Silver / Gold")

    if fallback_error:
        st.warning(
            "PostgreSQL was unavailable, so the app is showing labelled synthetic demo data. "
            f"Connection detail: {fallback_error}"
        )

    if page == "Portfolio Overview":
        render_portfolio(data)
    elif page == "Risk & Compliance":
        render_risk(data)
    else:
        render_customer(data)


if __name__ == "__main__":
    main()
