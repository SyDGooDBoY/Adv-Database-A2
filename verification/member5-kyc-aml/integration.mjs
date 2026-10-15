// Cross-module integration test.
//
// Loads the shared setup, then every member's scripts in the dependency order the
// members documented, runs the pipeline steps that are not triggered by the
// scripts themselves, then runs every member's validation file.
//
// Design note on expectations. Counts that belong to another member's layer
// (Bronze, shared Silver tables, the dimension) are MEASURED and printed, not
// asserted: their values depend on how much of Member 1's and Member 2's flow has
// run, and guessing them produces failures that say nothing about this module.
// Counts this module owns are asserted, because a change there is a regression.
//
// Three things a naive "run every .sql in order" script gets wrong, all handled:
//   1. Validation files are DO blocks that assert immediately, so they must run
//      after every pipeline, not at load time.
//   2. Member 1's own scripts already load B1 and B2; calling its incremental
//      procedure for an initial batch is an error it raises on purpose.
//   3. Member 6's routines are trigger functions, and Member 4's loader lives in
//      the gold schema. Neither is a silver procedure to CALL.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const here = dirname(fileURLToPath(import.meta.url));
const sqlRoot = join(here, "..", "..", "advanced-database-assignment2", "sql");

const MODULES = [
  { key: "hongfei", label: "Member 1 - incremental load" },
  { key: "mina", label: "Member 2 - identity matching" },
  { key: "kaijie", label: "Member 3 - survivorship" },
  { key: "guanbo", label: "Member 5 - KYC/AML", mine: true },
  { key: "dan", label: "Member 4 - analytics" },
  { key: "sunny", label: "Member 6 - security and audit" },
];

const TEST_FILE = /validation_tests|validation_demo/;
const results = [];
let currentPhase = "";
const db = new PGlite();

function phase(name) {
  currentPhase = name;
  console.log(`\n${"=".repeat(74)}\n${name}\n${"=".repeat(74)}`);
}

function record(label, ok, message) {
  results.push({ phase: currentPhase, label, ok, message });
}

async function runFile(label, path) {
  if (!existsSync(path)) {
    record(label, false, "file not found");
    console.log(`  MISS ${label}`);
    return;
  }
  try {
    await db.exec(readFileSync(path, "utf8"));
    record(label, true, "");
    console.log(`  ok   ${label}`);
  } catch (error) {
    const message = String(error.message).split("\n")[0];
    record(label, false, message);
    console.log(`  FAIL ${label}\n       ${message.slice(0, 150)}`);
  }
}

async function sql(label, statement) {
  try {
    await db.exec(statement);
    record(label, true, "");
    console.log(`  ok   ${label}`);
  } catch (error) {
    const message = String(error.message).split("\n")[0];
    record(label, false, message);
    console.log(`  FAIL ${label}\n       ${message.slice(0, 150)}`);
  }
}

async function count(query) {
  const result = await db.query(query);
  return result.rows[0].n;
}

async function measure(label, query) {
  const n = await count(query);
  console.log(`  ..   ${label}: ${n}`);
  return n;
}

async function expect(label, query, expected) {
  try {
    const n = await count(query);
    const ok = n === expected;
    record(label, ok, ok ? "" : `expected ${expected}, found ${n}`);
    console.log(`  ${ok ? "ok  " : "FAIL"} ${label}: ${n}${ok ? "" : ` (expected ${expected})`}`);
  } catch (error) {
    record(label, false, String(error.message).slice(0, 120));
    console.log(`  FAIL ${label}: ${String(error.message).slice(0, 120)}`);
  }
}

function moduleFiles(key, { exclude } = {}) {
  const dir = join(sqlRoot, key);
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((n) => n.endsWith(".sql"))
    .filter((n) => !(exclude ?? []).some((p) => p.test(n)))
    .sort()
    .map((n) => ({ name: n, path: join(dir, n) }));
}

// ------------------------------------------------------------------ phase 1
phase("Phase 1 - shared setup (00-49)");
for (const { name, path } of moduleFiles("00_shared_setup")) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) await runFile(name, path);
}

// ------------------------------------------------------------------ phase 2
phase("Phase 2 - load every member's scripts (validation files deferred)");
for (const m of MODULES) {
  const files = moduleFiles(m.key, { exclude: [TEST_FILE] });
  console.log(`\n-- ${m.label} (${files.length} file(s))`);
  for (const { name, path } of files) await runFile(`${m.key}/${name}`, path);
}

// ------------------------------------------------------------------ phase 3
phase("Phase 3 - pipeline steps that are not triggered by the scripts");
console.log("\n-- Member 3 procedure");
await sql("CALL silver.apply_member3_survivorship()", "CALL silver.apply_member3_survivorship();");
console.log("\n-- Member 4 loader (lives in the gold schema)");
await sql("CALL gold.load_dim_customer()", "CALL gold.load_dim_customer();");
console.log("\n-- Member 5 (mine), the five pipeline calls");
await sql("process_kyc_aml_batch B1-AMLKYC", "CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');");
await sql("process_kyc_aml_batch B2-AMLKYC", "CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');");
await sql("publish_compliance_cases", "CALL silver.publish_compliance_cases();");
await sql("progress_compliance_cases", "CALL silver.progress_compliance_cases(DATE '2026-09-30');");
await sql("refresh_compliance_exception_fact", "CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');");

// ------------------------------------------------------------------ phase 3b
phase("Phase 3b - what each layer holds (other members' layers measured)");
await measure("bronze customer rows", "SELECT count(*)::int AS n FROM bronze.raw_crm_customer");
await measure("bronze lending customer rows", "SELECT count(*)::int AS n FROM bronze.raw_lending_customer");
await measure("bronze KYC verification rows", "SELECT count(*)::int AS n FROM bronze.raw_kyc_verification");
await measure("source customer records (all sources)", "SELECT count(*)::int AS n FROM silver.source_customer_record");
await measure("gold dim_customer", "SELECT count(*)::int AS n FROM gold.dim_customer");
await measure("quality issues, all members", "SELECT count(*)::int AS n FROM silver.data_quality_issue");

console.log("\n  my own tables, asserted:");
await expect("my KYC events", "SELECT count(*)::int AS n FROM silver.kyc_verification_record", 9);
await expect("my AML events", "SELECT count(*)::int AS n FROM silver.aml_screening_result", 10);
await expect("my verification cases", "SELECT count(*)::int AS n FROM silver.special_verification_case", 2);
await expect("my AML cases", "SELECT count(*)::int AS n FROM silver.aml_case", 1);
await expect("my exception facts", "SELECT count(*)::int AS n FROM gold.fact_compliance_exception", 3);
await expect(
  "my quality issues",
  "SELECT count(*)::int AS n FROM silver.data_quality_issue WHERE validation_run_id LIKE 'KYC-AML-M5-%'",
  3,
);

// ------------------------------------------------------------------ phase 4
phase("Phase 4 - every member's validation file");
for (const m of MODULES) {
  for (const { name, path } of moduleFiles(m.key).filter((f) => TEST_FILE.test(f.name))) {
    await runFile(`${m.key}/${name}`, path);
  }
}

// ------------------------------------------------------------------ phase 5
phase("Phase 5 - my report, measured after every other module has run");
try {
  const result = await db.query(`
    SELECT
      (SELECT count(*)::int FROM silver.kyc_verification_record) AS kyc_events,
      (SELECT count(*)::int FROM silver.aml_screening_result) AS aml_events,
      (SELECT count(*)::int FROM silver.special_verification_case) AS verification_cases,
      (SELECT count(*)::int FROM silver.aml_case) AS aml_cases,
      (SELECT count(*)::int FROM gold.fact_compliance_exception) AS fact_rows,
      (SELECT count(*)::int FROM gold.vw_kyc_aml_exception_report) AS report_rows,
      (SELECT count(*)::int FROM gold.vw_kyc_aml_exception_report
        WHERE customer_key IS NOT NULL) AS rows_with_dimension_key;`);
  const r = result.rows[0];
  console.log(`  measured: ${JSON.stringify(r)}`);
  const expected = {
    kyc_events: 9,
    aml_events: 10,
    verification_cases: 2,
    aml_cases: 1,
    fact_rows: 3,
    report_rows: 3,
  };
  for (const [key, value] of Object.entries(expected)) {
    const ok = r[key] === value;
    record(`business result ${key}`, ok, ok ? "" : `expected ${value}, found ${r[key]}`);
    console.log(`  ${ok ? "ok  " : "FAIL"} ${key}: ${r[key]}${ok ? "" : ` (expected ${value})`}`);
  }
  console.log(`  ..   rows that gained a dimension key from Member 4: ${r.rows_with_dimension_key}`);
} catch (error) {
  record("business result", false, String(error.message).slice(0, 120));
  console.log(`  FAIL ${error.message}`);
}

// ------------------------------------------------------------------ summary
phase("Summary");
const byPhase = new Map();
for (const r of results) {
  if (!byPhase.has(r.phase)) byPhase.set(r.phase, { ok: 0, fail: 0 });
  byPhase.get(r.phase)[r.ok ? "ok" : "fail"] += 1;
}
for (const [name, c] of byPhase) {
  console.log(`  ${name.padEnd(56)} ok ${String(c.ok).padStart(3)}  fail ${c.fail}`);
}
const failures = results.filter((r) => !r.ok);
console.log(`\n  total ${results.length} checks, ${failures.length} failed`);
if (failures.length) {
  console.log("\n  failures:");
  for (const f of failures) console.log(`    [${f.phase}] ${f.label}: ${f.message.slice(0, 110)}`);
}
process.exit(failures.length ? 1 : 0);
