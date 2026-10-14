"""Final audit: every comment must be Chinese and state a purpose."""

from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "advanced-database-assignment2" / "sql" / "guanbo"


def has_cjk(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


print("=== 1. Comment language per file ===")
total_c = total_zh = 0
for path in sorted(MODULE.glob("*.sql")):
    lines = path.read_text(encoding="utf-8").splitlines()
    comments = [l for l in lines if l.lstrip().startswith("--")]
    zh = [l for l in comments if has_cjk(l)]
    total_c += len(comments)
    total_zh += len(zh)
    flag = "" if len(zh) == len(comments) else "  <-- has non-Chinese"
    print(f"  {path.name:<42} {len(comments):>3} comments, {len(zh):>3} Chinese{flag}")
print(f"  TOTAL {total_c} comments, {total_zh} Chinese ({total_zh*100//max(total_c,1)}%)")

print("\n=== 2. Any comment still without Chinese ===")
found = False
for path in sorted(MODULE.glob("*.sql")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = line.lstrip()
        if not s.startswith("--"):
            continue
        body = s.lstrip("-").strip()
        if not body or body.startswith("="):
            continue
        if not has_cjk(body):
            print(f"  {path.name}:{number}  {body[:86]}")
            found = True
if not found:
    print("  none - every comment carries Chinese")

print("\n=== 3. Longest comment blocks (should be short) ===")
for path in sorted(MODULE.glob("*.sql")):
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        if lines[i].lstrip().startswith("--"):
            j = i
            while j < len(lines) and lines[j].lstrip().startswith("--"):
                j += 1
            length = j - i
            if length >= 5:
                print(f"  {path.name}:{i+1}  {length} lines  | {lines[i].strip()[:60]}")
            i = j
        else:
            i += 1

print("\n=== 4. Size summary ===")
grand = 0
for path in sorted(MODULE.glob("*.sql")):
    n = len(path.read_text(encoding="utf-8").splitlines())
    grand += n
    print(f"  {path.name:<42} {n:>4}")
print(f"  {'TOTAL':<42} {grand:>4}")
