"""Compare each working file against its committed version and report every
non-comment line that changed, so an accidental deletion cannot hide."""

import subprocess
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "advanced-database-assignment2" / "sql" / "guanbo"
REPO = "Adv-Database-A2"


def git_show(path: str) -> str:
    result = subprocess.run(
        ["git", "-C", REPO, "show", f"HEAD:{path}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout


def is_comment(line: str) -> bool:
    return line.lstrip().startswith("--")


problems = 0
for path in sorted(MODULE.glob("*.sql")):
    rel = f"advanced-database-assignment2/sql/guanbo/{path.name}"
    old = git_show(rel).splitlines()
    new = path.read_text(encoding="utf-8").splitlines()

    old_code = [l.strip() for l in old if not is_comment(l) and l.strip()]
    new_code = [l.strip() for l in new if not is_comment(l) and l.strip()]

    if old_code != new_code:
        problems += 1
        print(f"\n{path.name}: CODE CHANGED")
        # report the first divergences
        for i, (a, b) in enumerate(zip(old_code, new_code)):
            if a != b:
                print(f"  first difference at code line {i+1}:")
                print(f"    HEAD:    {a[:90]}")
                print(f"    WORKING: {b[:90]}")
                break
        else:
            print(f"    length differs: HEAD {len(old_code)} vs WORKING {len(new_code)}")
            longer, shorter = (old_code, new_code) if len(old_code) > len(new_code) else (new_code, old_code)
            label = "HEAD only" if len(old_code) > len(new_code) else "WORKING only"
            extra = [l for l in longer if l not in shorter]
            for l in extra[:5]:
                print(f"    {label}: {l[:90]}")
    else:
        print(f"{path.name}: code identical, only comments changed")

    # comment line counts
    oc = sum(1 for l in old if is_comment(l))
    nc = sum(1 for l in new if is_comment(l))
    print(f"    lines: {len(old)} -> {len(new)}   comments: {oc} -> {nc}")

print(f"\nfiles with code changes: {problems}")
