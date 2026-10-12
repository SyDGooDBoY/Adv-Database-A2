// End-to-end verification for the Member 5 KYC/AML module.
//
// PGlite is a real PostgreSQL build compiled to WebAssembly, so this exercises
// the actual server: plpgsql bodies, constraints, indexes, upserts and the
// validation tests. The static parser check in validate_syntax.py cannot see
// inside a plpgsql body; this can.

import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const moduleDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "advanced-database-assignment2", "sql", "guanbo");
const sqlRoot = join(moduleDir, "..");
const sharedDir = join(sqlRoot, "00_shared_setup");

const REFERENCE_DATE = "2026-09-30";

const db = new PGlite();


async function run(label, sql) {
  const started = Date.now();
  try {
    await db.exec(sql);
    const ms = Date.now() - started;
    console.log(`  ok   ${label}  (${ms} ms)`);
    return true;
  } catch (error) {
    console.log(`  FAIL ${label}`);
    console.log(`       ${String(error.message).split("\n").slice(0, 12).join("\n       ")}`);
    if (error.position) {
      const position = Number(error.position);
      const before = sql.slice(0, position);
      const line = before.split("\n").length;
      const lines = sql.split("\n");
      console.log(`       at line ${line}: ${(lines[line - 1] ?? "").trim().slice(0, 160)}`);
    }
    return false;
  }
}

console.log("1. shared database setup (00-49)");
const sharedFiles = readdirSync(sharedDir)
  .filter((name) => name.endsWith(".sql"))
  .filter((name) => {
    const order = Number.parseInt(name.slice(0, 2), 10);
    return Number.isFinite(order) && order <= 49;
  })
  .sort();

let failed = 0;
for (const name of sharedFiles) {
  const sql = readFileSync(join(sharedDir, name), "utf8");
  if (!(await run(name, sql))) failed += 1;
}
if (failed > 0) {
  console.log(`\n${failed} shared setup file(s) failed; stopping.`);
  process.exit(1);
}

console.log("\n2. Member 5 module scripts (run order)");
const moduleFiles = readdirSync(moduleDir)
  .filter((name) => /^\d\d_.*\.sql$/.test(name))
  .sort();

let deferredAssertions = null;
for (const name of moduleFiles) {
  let sql = readFileSync(join(moduleDir, name), "utf8");
  if (name.startsWith("08")) {
    // The DO block asserts the pipeline results, so it can only run after the
    // pipeline has executed. Load the rest of the file now and defer that block.
    const marker = "-- Report-ready evidence.";
    deferredAssertions = sql.slice(0, sql.indexOf(marker));
    sql = sql.slice(sql.indexOf(marker));
  }
  if (!(await run(name, sql))) failed += 1;
}
if (failed > 0) {
  console.log(`\n${failed} module file(s) failed; stopping before the run steps.`);
  process.exit(1);
}

console.log("\n3. pipeline run");
const calls = [
  ["process B1-AMLKYC", `CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '${REFERENCE_DATE}');`],
  ["process B2-AMLKYC", `CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '${REFERENCE_DATE}');`],
  ["publish cases", "CALL silver.publish_compliance_cases();"],
  ["progress cases", `CALL silver.progress_compliance_cases(DATE '${REFERENCE_DATE}');`],
  ["refresh exception fact", `CALL gold.refresh_compliance_exception_fact(DATE '${REFERENCE_DATE}');`],
];
for (const [label, sql] of calls) {
  if (!(await run(label, sql))) failed += 1;
}

// A procedure that swallows an internal error would otherwise look successful,
// so assert the state the pipeline is supposed to have produced.
console.log("\n3b. pipeline outcome");
const outcomes = [
  ["published KYC events", "SELECT count(*)::int AS n FROM silver.kyc_verification_record", 9],
  ["published AML events", "SELECT count(*)::int AS n FROM silver.aml_screening_result", 10],
  ["registered findings", "SELECT count(*)::int AS n FROM silver.data_quality_issue WHERE validation_run_id LIKE 'KYC-AML-M5-%'", 3],
  ["verification cases", "SELECT count(*)::int AS n FROM silver.special_verification_case", 2],
  ["AML cases", "SELECT count(*)::int AS n FROM silver.aml_case", 1],
  ["exception fact rows", "SELECT count(*)::int AS n FROM gold.fact_compliance_exception", 3],
];
for (const [label, sql, expected] of outcomes) {
  try {
    const result = await db.query(sql);
    const actual = result.rows[0].n;
    if (actual === expected) {
      console.log(`  ok   ${label}: ${actual}`);
    } else {
      failed += 1;
      console.log(`  FAIL ${label}: expected ${expected}, found ${actual}`);
    }
  } catch (error) {
    failed += 1;
    console.log(`  FAIL ${label}: ${error.message}`);
  }
}
console.log("\n4. acceptance tests (08_validation_tests.sql)");
if (deferredAssertions === null) {
  failed += 1;
  console.log("  FAIL the assertion block was not found in 08_validation_tests.sql");
} else if (!(await run("assertions", deferredAssertions))) {
  failed += 1;
}

console.log("\n5. reported output");
const reportQueries = [
  ["exception report", `
    SELECT exception_source_type, exception_type, exception_status, severity,
           opened_date, resolved_date, as_of_date, days_open, customer_name
    FROM gold.vw_kyc_aml_exception_report
    ORDER BY exception_source_type, exception_type, opened_date;`],
  ["exception summary", `
    SELECT customer_name, exception_source_type, exception_type, exception_count,
           open_exception_count, resolved_exception_count, longest_days_open, highest_severity
    FROM gold.vw_compliance_exception_summary
    ORDER BY exception_source_type, exception_type, customer_name;`],
  ["kyc status", `
    SELECT kyc_status, count(*) AS customers,
           sum(verification_count) AS verifications,
           sum(reusable_verification_count) AS reusable
    FROM silver.customer_kyc_status(DATE '${REFERENCE_DATE}')
    GROUP BY kyc_status ORDER BY kyc_status;`],
  ["findings by rule", `
    SELECT rule_name, entity_name, severity, count(*) AS findings
    FROM silver.data_quality_issue
    WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    GROUP BY rule_name, entity_name, severity
    ORDER BY rule_name;`],
  ["cases", `
    SELECT case_source, case_type, case_status, count(*) AS cases
    FROM (
      SELECT 'VERIFICATION' AS case_source, case_type, case_status
      FROM silver.special_verification_case
      UNION ALL
      SELECT 'AML', case_type, case_status FROM silver.aml_case
    ) all_cases
    GROUP BY case_source, case_type, case_status
    ORDER BY case_source, case_type;`],
];

for (const [label, sql] of reportQueries) {
  try {
    const result = await db.query(sql);
    console.log(`\n--- ${label} ---`);
    console.table(result.rows);
  } catch (error) {
    failed += 1;
    console.log(`  FAIL ${label}: ${error.message}`);
  }
}

console.log(`\n${failed === 0 ? "ALL CHECKS PASSED" : `${failed} FAILURE(S)`}`);
process.exit(failed === 0 ? 0 : 1);
