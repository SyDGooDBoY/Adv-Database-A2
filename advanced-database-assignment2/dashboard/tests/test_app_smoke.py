from pathlib import Path

from streamlit.testing.v1 import AppTest


def test_all_three_dashboard_pages_render(monkeypatch):
    monkeypatch.setenv("DASHBOARD_USE_DEMO_DATA", "true")
    app_path = Path(__file__).resolve().parents[1] / "app.py"
    app = AppTest.from_file(app_path, default_timeout=20)

    app.run()
    assert not app.exception

    app.radio[0].set_value("Risk & Compliance").run()
    assert not app.exception

    app.radio[0].set_value("Customer Risk Profile").run()
    assert not app.exception
