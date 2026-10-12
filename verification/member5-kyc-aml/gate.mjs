// Final gate for the Member 5 module: encoding, syntax, and end-to-end execution.
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const moduleDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "advanced-database-assignment2", "sql", "guanbo");
const python = process.env.DSH_PYTHON;
let failed = 0;

// 1. No BOM, and no CRLF surprises inside dollar-quoted bodies.
console.log("1. file encoding");
for (const name of readdirSync(moduleDir).filter((n) => /\.(sql|md|py)$/.test(n)).sort()) {
  const raw = readFileSync(join(moduleDir, name));
  const hasBom = raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf;
  if (hasBom) {
    failed += 1;
    console.log(`  FAIL ${name} starts with a UTF-8 BOM, which PostgreSQL rejects`);
  } else {
    console.log(`  ok   ${name}`);
  }
}

// 2. Static parse with the real PostgreSQL parser.
console.log("\n2. pglast parse (PostgreSQL parser)");
try {
  const output = execFileSync(python, [join(moduleDir, "validate_syntax.py")], {
    encoding: "utf8",
    env: { ...process.env, PYTHONIOENCODING: "utf-8" },
  });
  const summary = output.trim().split("\n").slice(-1)[0];
  console.log(`  ok   ${summary}`);
} catch (error) {
  failed += 1;
  console.log(`  FAIL ${String(error.stdout ?? error.message).slice(0, 800)}`);
}

console.log(`\n${failed === 0 ? "FINAL GATE PASSED" : `${failed} FAILURE(S)`}`);
process.exit(failed === 0 ? 0 : 1);
