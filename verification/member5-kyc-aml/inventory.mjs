// Inventory of what the module actually creates, for the report appendix.
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const moduleDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "advanced-database-assignment2", "sql", "guanbo");
const sharedDir = join(moduleDir, "..", "00_shared_setup");
const db = new PGlite();

for (const name of readdirSync(sharedDir).filter((n) => /^\d\d_/.test(n)).sort()) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) {
    await db.exec(readFileSync(join(sharedDir, name), "utf8"));
  }
}
for (const name of readdirSync(moduleDir).filter((n) => /^0[0-7]_.*\.sql$/.test(n)).sort()) {
  await db.exec(readFileSync(join(moduleDir, name), "utf8"));
}

console.log("=== CHECK constraints added by this module ===");
const checks = await db.query(`
  SELECT conname, conrelid::regclass::text AS table_name
  FROM pg_constraint
  WHERE contype = 'c' AND connamespace = 'silver'::regnamespace
     OR (contype = 'c' AND connamespace = 'gold'::regnamespace)
  ORDER BY table_name, conname;`);
for (const row of checks.rows) console.log(`  ${row.table_name}  ${row.conname}`);

console.log("\n=== unique indexes on the compliant fact ===");
const indexes = await db.query(`
  SELECT indexname, indexdef FROM pg_indexes
  WHERE schemaname = 'gold' AND tablename = 'fact_compliance_exception';`);
for (const row of indexes.rows) console.log(`  ${row.indexdef}`);

console.log("\n=== objects created by this module ===");
const objects = await db.query(`
  SELECT n.nspname AS schema, c.relname AS name,
         CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' END AS kind
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('silver', 'gold') AND c.relkind IN ('r', 'v')
    AND (c.relname IN ('kyc_verification_record','special_verification_case',
                       'aml_screening_result','aml_case','fact_compliance_exception')
         OR c.relname LIKE 'vw_kyc%' OR c.relname LIKE 'vw_compliance%')
  ORDER BY n.nspname, c.relname;`);
for (const row of objects.rows) console.log(`  ${row.schema}.${row.name} (${row.kind})`);

console.log("\n=== routines created by this module ===");
const routines = await db.query(`
  SELECT p.proname, p.prokind,
         pg_get_function_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('silver', 'gold')
    AND p.proname ~ 'kyc|aml|compliance|stage_bronze|record_event|resolve_event|pick_top|customer_kyc'
  ORDER BY p.proname;`);
for (const row of routines.rows) {
  const kind = row.prokind === 'p' ? 'procedure' : 'function';
  console.log(`  [${kind}] ${row.proname}(${row.args})`);
}
console.log(`\ntotals: ${objects.rows.length} relations, ${routines.rows.length} routines, ${checks.rows.length} check constraints`);
