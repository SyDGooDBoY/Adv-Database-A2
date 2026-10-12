// Print the exact column lists of the tables this module owns or writes to, so
// the comment script matches every column name and type.
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

const targets = [
  ["silver", "kyc_verification_record"],
  ["silver", "special_verification_case"],
  ["silver", "aml_screening_result"],
  ["silver", "aml_case"],
  ["gold", "fact_compliance_exception"],
  ["silver", "data_quality_issue"],
  ["silver", "data_lineage_record"],
  ["bronze", "raw_kyc_verification"],
  ["bronze", "raw_aml_screening"],
];

for (const [schema, table] of targets) {
  const result = await db.query(
    `SELECT column_name, data_type, is_nullable
     FROM information_schema.columns
     WHERE table_schema = $1 AND table_name = $2
     ORDER BY ordinal_position`,
    [schema, table],
  );
  console.log(`\n### ${schema}.${table}  (${result.rows.length} 列)`);
  for (const row of result.rows) {
    const nullable = row.is_nullable === "YES" ? "" : " NOT NULL";
    console.log(`  ${row.column_name} ${row.data_type}${nullable}`);
  }
}

// Also list the objects this module created, so every one can be commented.
const objects = await db.query(`
  SELECT n.nspname AS schema, c.relname AS name, c.relkind AS kind
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('silver', 'gold')
    AND c.relkind IN ('v', 'r')
    AND (c.relname LIKE 'vw_%' OR c.relname LIKE 'fact_%'
         OR c.relname IN ('kyc_verification_record','special_verification_case',
                          'aml_screening_result','aml_case'))
  ORDER BY n.nspname, c.relname;`);
console.log("\n### 视图与表");
console.table(objects.rows);

const routines = await db.query(`
  SELECT n.nspname AS schema, p.proname AS name, p.prokind AS kind,
         pg_get_function_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('silver', 'gold', 'bronze')
    AND p.proname ~ 'kyc|aml|compliance'
  ORDER BY n.nspname, p.proname;`);
console.log("### 函数与过程");
console.table(routines.rows);
