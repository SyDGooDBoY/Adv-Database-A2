"""Validate every SQL file in the Member 5 module with the real PostgreSQL parser.

pglast wraps libpg_query, the actual PostgreSQL parser, so a file that parses
here is syntactically acceptable to PostgreSQL 15. The checks go a little
further than parsing: dollar-quote balance and statement counts are reported so
an accidentally unterminated function body is caught even when the parser
happens to accept the file.
"""

import re
import sys
from pathlib import Path

import pglast

MODULE_DIR = Path(__file__).resolve().parent


def dollar_quotes(sql: str) -> tuple[list[str], str | None]:
    """Return the dollar-quote tags in order and any tag left open."""
    stack: list[str] = []
    tags: list[str] = []
    for match in re.finditer(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql):
        tag = match.group(0)
        if stack and stack[-1] == tag:
            stack.pop()
        else:
            stack.append(tag)
            tags.append(tag)
    return tags, (stack[-1] if stack else None)


def validate(path: Path) -> list[str]:
    problems: list[str] = []
    sql = path.read_text(encoding="utf-8")

    tags, unclosed = dollar_quotes(sql)
    if unclosed:
        problems.append(f"unterminated dollar quote {unclosed}")

    try:
        statements = pglast.parse_sql(sql)
    except Exception as error:  # pglast raises its own error type
        problems.append(f"parse error: {error}")
        return problems

    print(f"  parsed {len(statements):>2} statements, {len(tags)} dollar-quoted bodies")

    if path.suffix == ".sql" and sql.strip() and not statements:
        problems.append("no statements found")

    return problems


def main() -> int:
    combined = []
    files = sorted(MODULE_DIR.glob("*.sql"))
    if not files:
        print("no SQL files found", file=sys.stderr)
        return 1

    failed = 0
    for path in files:
        print(f"{path.name}")
        problems = validate(path)
        if problems:
            failed += 1
            for problem in problems:
                print(f"  FAIL {problem}")
        else:
            print("  ok")
        combined.append(path.read_text(encoding="utf-8"))

    print("\ncombined module (all files, run order)")
    try:
        statements = pglast.parse_sql("\n".join(combined))
        print(f"  parsed {len(statements)} statements in one pass")
    except Exception as error:
        failed += 1
        print(f"  FAIL combined parse error: {error}")

    print(f"\n{len(files) - failed} of {len(files)} files validated")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
