// Dump the tables, columns, views and routines this module owns, so object
// descriptions can be written against the real structure rather than from memory.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const here = dirname(fileURLToPath(import.meta.url));
const sqlRoot = join(here, "..", "..", "advanced-database-assignment2", "sql");
const db = new PGlite();

const run = async (path) => db.exec(readFileSync(path, "utf8"));

for (const name of readdirSync(join(sqlRoot, "00_shared_setup")).filter((n) => n.endsWith(".sql")).sort()) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) await run(join(sqlRoot, "00_shared_setup", name));
}
for (const name of readdirSync(join(sqlRoot, "guanbo")).filter((n) => n.endsWith(".sql") && !/08_/.test(n)).sort()) {
  await run(join(sqlRoot, "guanbo", name));
}

const OWNED = [
  ["table", "silver", "kyc_verification_record"],
  ["table", "silver", "special_verification_case"],
  ["table", "silver", "aml_screening_result"],
  ["table", "silver", "aml_case"],
  ["table", "gold", "fact_compliance_exception"],
];

for (const [, schema, table] of OWNED) {
  const result = await db.query(
    `SELECT column_name, data_type, is_nullable
     FROM information_schema.columns
     WHERE table_schema = $1 AND table_name = $2
     ORDER BY ordinal_position`,
    [schema, table],
  );
  console.log(`\n${schema}.${table}  (${result.rows.length} columns)`);
  for (const row of result.rows) {
    console.log(`    ${row.column_name.padEnd(32)} ${row.data_type.padEnd(26)} ${row.is_nullable === "YES" ? "null" : "not null"}`);
  }
}

console.log("\nviews");
const views = await db.query(
  `SELECT table_schema, table_name FROM information_schema.views
   WHERE table_schema IN ('silver','gold') ORDER BY 1,2`,
);
for (const row of views.rows) console.log(`    ${row.table_schema}.${row.table_name}`);

console.log("\nroutines");
const routines = await db.query(
  `SELECT n.nspname AS schema_name, p.proname AS name,
          pg_get_function_identity_arguments(p.oid) AS args,
          CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END AS kind
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('silver','gold')
     AND p.proname IN (
       'kyc_verification_id','aml_screening_id','compliance_exception_fact_id',
       'detect_kyc_verification_issues','detect_aml_screening_issues',
       'compliance_rule_case_type','register_compliance_finding','find_or_open_case',
       'find_or_open_verification_case','find_or_open_aml_case','resolve_compliance_case',
       'resolve_event_identity','customer_kyc_status','stage_bronze_batch',
       'record_event_lineage','load_kyc_aml_customer_identity',
       'publish_kyc_verification_batch','publish_aml_screening_batch',
       'process_kyc_aml_batch','publish_compliance_cases','progress_compliance_cases',
       'refresh_compliance_exception_fact')
   ORDER BY 1,2`,
);
for (const row of routines.rows) {
  console.log(`    ${row.kind.padEnd(10)} ${row.schema_name}.${row.name}(${row.args})`);
}
