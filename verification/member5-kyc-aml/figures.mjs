// Print the demonstration figures from a clean run, so the README matches reality.
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const moduleDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "advanced-database-assignment2", "sql", "module5_guanbo");
const sqlRoot = join(moduleDir, "..");
const sharedDir = join(sqlRoot, "00_shared_setup");
const db = new PGlite();
for (const name of readdirSync(sharedDir).filter((n) => /^\d\d_/.test(n)).sort()) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) {
    await db.exec(readFileSync(join(sharedDir, name), "utf8"));
  }
}
for (const name of readdirSync(moduleDir).filter((n) => /^0[0-7]_.*\.sql$/.test(n)).sort()) {
  await db.exec(readFileSync(join(moduleDir, name), "utf8"));
}
await db.exec("CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');");
await db.exec("CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');");
await db.exec("CALL silver.publish_compliance_cases();");
await db.exec("CALL silver.progress_compliance_cases(DATE '2026-09-30');");
await db.exec("CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');");

const report = async (label, sql) => {
  const result = await db.query(sql);
  console.log(`\n=== ${label} ===`);
  console.table(result.rows);
};

await report("counts", `
  SELECT 'KYC events published' AS metric, count(*)::int AS value FROM silver.kyc_verification_record
  UNION ALL SELECT 'AML events published', count(*)::int FROM silver.aml_screening_result
  UNION ALL SELECT 'quality issues registered', count(*)::int FROM silver.data_quality_issue WHERE validation_run_id LIKE 'KYC-AML-M5-%'
  UNION ALL SELECT 'verification cases', count(*)::int FROM silver.special_verification_case
  UNION ALL SELECT 'AML cases', count(*)::int FROM silver.aml_case
  UNION ALL SELECT 'exception fact rows', count(*)::int FROM gold.fact_compliance_exception
  UNION ALL SELECT 'identity records staged', count(*)::int FROM silver.source_customer_record WHERE source_system_id = 'AMLKYC'
  UNION ALL SELECT 'customers staged', count(*)::int FROM silver.customer_master;`);

await report("findings", `
  SELECT rule_name, entity_name, severity, issue_status, count(*)::int AS findings
  FROM silver.data_quality_issue WHERE validation_run_id LIKE 'KYC-AML-M5-%'
  GROUP BY rule_name, entity_name, severity, issue_status ORDER BY rule_name;`);

await report("cases", `
  SELECT case_source, case_type, case_status, count(*)::int AS cases FROM (
    SELECT 'VERIFICATION' AS case_source, case_type, case_status FROM silver.special_verification_case
    UNION ALL SELECT 'AML', case_type, case_status FROM silver.aml_case
  ) c GROUP BY case_source, case_type, case_status ORDER BY case_source, case_type;`);

await report("exception report", `
  SELECT exception_source_type, exception_type, exception_status, severity,
         opened_date::text, resolved_date::text, days_open, customer_name
  FROM gold.vw_kyc_aml_exception_report ORDER BY exception_source_type, exception_type;`);

await report("kyc status", `
  SELECT kyc_status, count(*)::int AS customers, sum(verification_count)::int AS verifications,
         sum(reusable_verification_count)::int AS reusable
  FROM silver.customer_kyc_status(DATE '2026-09-30') GROUP BY kyc_status ORDER BY kyc_status;`);
