$ErrorActionPreference = "Stop"
$DashboardRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DashboardPython = Join-Path $DashboardRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $DashboardPython)) {
    throw "Dashboard virtual environment not found. Follow README.md to create .venv and install requirements.txt."
}

& $DashboardPython -m streamlit run (Join-Path $DashboardRoot "app.py")
