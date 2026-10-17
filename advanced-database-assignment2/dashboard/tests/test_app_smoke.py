from pathlib import Path

from streamlit.testing.v1 import AppTest


def test_all_three_dashboard_pages_render(monkeypatch):
    monkeypatch.setenv("DASHBOARD_USE_DEMO_DATA", "true")
    app_path = Path(__file__).resolve().parents[1] / "app.py"
    app = AppTest.from_file(app_path, default_timeout=20)

    app.run()
    assert not app.exception
    assert "Daily net profit" in [metric.label for metric in app.metric]

    app.radio[0].set_value("Risk & Compliance").run()
    assert not app.exception
    scope_notes = [message.value for message in app.info]
    assert any(
        "13 identified customers" in note
        and "10 customers with an account or loan" in note
        and "3 identified customers have no account or loan" in note
        for note in scope_notes
    )

    app.radio[0].set_value("Customer Risk Profile").run()
    assert not app.exception
