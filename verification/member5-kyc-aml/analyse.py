"""Check whether every object defined by 07 is actually used elsewhere, and look
for dangling references across the module."""

import re
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "advanced-database-assignment2" / "sql" / "module5_guanbo"
files = sorted(MODULE.glob("*.sql"))
texts = {f.name: f.read_text(encoding="utf-8") for f in files}
all_text = "\n".join(texts.values())

print("=== Is every object defined by 07 used outside 07? ===")
f07 = texts.get("07_create_compliance_reporting_views.sql", "")
others = "\n".join(v for k, v in texts.items() if k != "07_create_compliance_reporting_views.sql")
tests = texts.get("08_validation_tests.sql", "")

for obj in (
    "customer_kyc_status",
    "vw_kyc_aml_exception_report",
    "vw_compliance_exception_summary",
    "vw_kyc_aml_exception_lineage",
):
    in07 = len(re.findall(re.escape(obj), f07))
    in_others = len(re.findall(re.escape(obj), others))
    in_tests = len(re.findall(re.escape(obj), tests))
    verdict = "USED" if in_others else "NOT USED"
    print(f"  {obj:<34} in07={in07:>2}  elsewhere={in_others:>2}  (tests={in_tests})  -> {verdict}")

print("\n=== 07 line breakdown ===")
lines07 = f07.splitlines()
comments = sum(1 for line in lines07 if line.lstrip().startswith("--"))
print(f"  total {len(lines07)}   comments {comments}   code {len(lines07) - comments}")

print("\n=== Dangling function calls (called but never defined) ===")
# A function call is written as schema.name( with no space before the bracket. A
# table reference always has a space after the name (an alias, or nothing), so
# requiring the bracket immediately after the name separates the two cases.
defined = set(re.findall(r"CREATE OR REPLACE (?:FUNCTION|PROCEDURE) (?:silver|gold)\.(\w+)", all_text))
called = set(re.findall(r"(?:silver|gold)\.(\w+)\(", all_text))
dangling = sorted(called - defined)
print(f"  defined={len(defined)}  called={len(called)}")
if dangling:
    print(f"  dangling: {dangling}")
else:
    print("  dangling: none - every call resolves to a definition")

print("\n=== Objects defined but never referenced twice (possible dead code) ===")
for name in sorted(defined):
    uses = len(re.findall(re.escape(name), all_text))
    if uses <= 1:
        print(f"  {name}  (only its own definition)")

print("\n=== Views referenced anywhere? ===")
for name in sorted(re.findall(r"CREATE OR REPLACE VIEW (?:silver|gold)\.(\w+)", all_text)):
    uses = len(re.findall(re.escape(name), all_text))
    print(f"  {name:<38} total mentions {uses}")
