"""Deterministic synthetic fallback data for UI development and marking demos."""

from __future__ import annotations

import pandas as pd


DATES = pd.to_datetime(["2026-09-01", "2026-09-08", "2026-09-15"])


def _portfolio_health() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "snapshot_date": DATES,
            "customer_count": [10, 10, 10],
            "partial_customer_count": [2, 1, 1],
            "unassessed_customer_count": [2, 1, 0],
            "total_account_balance": [482_000, 501_500, 526_800],
            "total_outstanding_loans": [314_000, 307_500, 298_200],
            "total_overdraft_balance": [18_500, 17_200, 15_900],
            "total_debt": [332_500, 324_700, 314_100],
            "total_credit_exposure": [354_000, 346_100, 334_800],
            "total_net_profit": [7_900, 8_350, 9_120],
        }
    )


CUSTOMERS = [
    ("CUST-001", "Alice Johnson", "ACTIVE", "LOW", 18),
    ("CUST-002", "Daniel Smith", "REVIEW", "HIGH", 82),
    ("CUST-003", "Ethan Brown", "ACTIVE", "MEDIUM", 52),
    ("CUST-004", "Noah Chen", "ACTIVE", "HIGH", 78),
    ("CUST-005", "Olivia Brooks", "ACTIVE", "HIGH", 88),
    ("CUST-006", "Leo Martin", "ACTIVE", "MEDIUM", 60),
    ("CUST-007", "Sophia Wilson", "ACTIVE", "LOW", 22),
    ("CUST-008", "Mason Davis", "ACTIVE", "MEDIUM", 48),
    ("CUST-009", "Emma Taylor", "ACTIVE", "LOW", 20),
    ("CUST-010", "Liam Anderson", "ACTIVE", "MEDIUM", 55),
    ("CUST-011", "Ava Thomas", "NO_CURRENT_SOURCE", "LOW", 25),
    ("CUST-012", "Mia Moore", "ACTIVE", "MEDIUM", 50),
    ("CUST-013", "James White", "ACTIVE", "LOW", 16),
]


def _compliance_labels(customer_id: str) -> tuple[str, str]:
    """Return deterministic KYC/AML labels for the full identified population."""
    kyc = "VERIFIED"
    aml = "CLEAR"
    if customer_id in {"CUST-004", "CUST-006"}:
        kyc = "EXPIRED"
    if customer_id == "CUST-005":
        aml = "POTENTIAL_MATCH"
    if customer_id == "CUST-002":
        kyc = "UNKNOWN"
    return kyc, aml


def _customer_profile() -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for date_index, snapshot_date in enumerate(DATES):
        # The financial snapshot contains only customers with an account or loan.
        for customer_index, (customer_id, name, status, risk, score) in enumerate(
            CUSTOMERS[:10]
        ):
            balance = 18_000 + customer_index * 3_400 + date_index * 750
            loan = max(0, 48_000 - customer_index * 2_100 - date_index * 650)
            overdraft = 1_800 if customer_index % 4 == 0 else 0
            debt = loan + overdraft
            kyc, aml = _compliance_labels(customer_id)
            rows.append(
                {
                    "snapshot_date": snapshot_date,
                    "customer_id": customer_id,
                    "customer_full_name": name,
                    "customer_status": status,
                    "total_account_balance": balance,
                    "total_outstanding_loans": loan,
                    "total_overdraft_balance": overdraft,
                    "total_debt": debt,
                    "total_credit_exposure": debt * 1.08,
                    "net_profit": 420 + customer_index * 35 + date_index * 20,
                    "financial_data_status": "PARTIAL" if customer_index == 1 else "COMPLETE",
                    "kyc_status": kyc,
                    "aml_risk_level": aml,
                    "risk_score": score,
                    "risk_rating": risk,
                    "kyc_risk_rating": "HIGH" if kyc in {"EXPIRED", "UNKNOWN"} else "LOW",
                    "aml_risk_rating": "HIGH" if aml != "CLEAR" else "LOW",
                    "assessment_reason": f"Synthetic {risk.lower()}-risk rule for exposure and compliance status",
                    "assessment_rule": "dashboard_demo_rules",
                    "assessment_rule_version": "1",
                }
            )
    return pd.DataFrame(rows)


def _risk_distribution(profile: pd.DataFrame) -> pd.DataFrame:
    return (
        profile.groupby(["snapshot_date", "risk_rating"], as_index=False)
        .agg(customer_count=("customer_id", "count"), total_debt=("total_debt", "sum"))
    )


def _compliance_status() -> pd.DataFrame:
    # Compliance covers all identified customers, including the three customers
    # who do not have an account or loan and therefore are not in the snapshot.
    rows: list[dict[str, object]] = []
    for snapshot_date in DATES:
        for customer_id, *_ in CUSTOMERS:
            kyc, aml = _compliance_labels(customer_id)
            rows.append(
                {
                    "snapshot_date": snapshot_date,
                    "customer_id": customer_id,
                    "kyc_status": kyc,
                    "aml_risk_level": aml,
                }
            )
    population = pd.DataFrame(rows)
    return (
        population.groupby(
            ["snapshot_date", "kyc_status", "aml_risk_level"], as_index=False
        )
        .agg(customer_count=("customer_id", "count"))
    )


def _compliance_exceptions() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "exception_fact_id": "EXC-001",
                "exception_source_type": "VERIFICATION",
                "exception_type": "KYC_GAP",
                "exception_status": "OPEN",
                "severity": "MEDIUM",
                "opened_date": pd.Timestamp("2026-09-01"),
                "resolved_date": pd.NaT,
                "as_of_date": pd.Timestamp("2026-09-30"),
                "days_open": 29,
                "customer_id": "CUST-004",
                "customer_name": "Noah Chen",
                "case_reason": "Required verification document is missing",
            },
            {
                "exception_fact_id": "EXC-002",
                "exception_source_type": "VERIFICATION",
                "exception_type": "STATUS_DISCREPANCY",
                "exception_status": "OPEN",
                "severity": "HIGH",
                "opened_date": pd.Timestamp("2026-09-15"),
                "resolved_date": pd.NaT,
                "as_of_date": pd.Timestamp("2026-09-30"),
                "days_open": 15,
                "customer_id": "CUST-006",
                "customer_name": "Leo Martin",
                "case_reason": "Verification expired before the reporting date",
            },
            {
                "exception_fact_id": "EXC-003",
                "exception_source_type": "AML",
                "exception_type": "AML_SCREENING_REVIEW",
                "exception_status": "IN_REVIEW",
                "severity": "MEDIUM",
                "opened_date": pd.Timestamp("2026-09-15"),
                "resolved_date": pd.NaT,
                "as_of_date": pd.Timestamp("2026-09-30"),
                "days_open": 15,
                "customer_id": "CUST-005",
                "customer_name": "Olivia Brooks",
                "case_reason": "Potential watchlist match requires review",
            },
        ]
    )


def load_demo_data() -> dict[str, pd.DataFrame]:
    """Return a complete, deterministic in-memory dashboard dataset."""
    profile = _customer_profile()
    return {
        "portfolio_health": _portfolio_health(),
        "risk_distribution": _risk_distribution(profile),
        "customer_profile": profile,
        "compliance_status": _compliance_status(),
        "compliance_exceptions": _compliance_exceptions(),
    }
