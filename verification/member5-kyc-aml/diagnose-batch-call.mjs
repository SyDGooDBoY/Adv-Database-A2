// Isolate one incremental call: does calling process_incremental_batch register
// the B2 batch, and what does the procedure report while doing it?

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const here = dirname(fileURLToPath(import.meta.url));
const sqlRoot = join(here, "..", "..", "advanced-database-assignment2", "sql");
const db = new PGlite();

const run = async (label, path) => {
  try {
    await db.exec(readFileSync(path, "utf8"));
    console.log(`  ok   ${label}`);
    return true;
  } catch (error) {
    console.log(`  FAIL ${label}: ${String(error.message).split("\n")[0].slice(0, 150)}`);
    return false;
  }
};

// Minimal load: shared setup then Member 1 only, nothing else can interfere.
for (const name of readdirSync(join(sqlRoot, "00_shared_setup")).filter((n) => n.endsWith(".sql")).sort()) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) await run(name, join(sqlRoot, "00_shared_setup", name));
}
for (const name of readdirSync(join(sqlRoot, "hongfei")).filter((n) => n.endsWith(".sql")).sort()) {
  if (/05_run_|06_run_|07_validation/.test(name)) continue; // call them ourselves
  await run(`hongfei/${name}`, join(sqlRoot, "hongfei", name));
}

const state = async (label) => {
  const b = await db.query(
    `SELECT batch_id, load_status FROM silver.ingestion_batch ORDER BY batch_id`,
  );
  const s = await db.query(
    `SELECT batch_id, load_type, load_status FROM source_systems.ingestion_batch ORDER BY batch_id`,
  );
  console.log(`\n  ${label}`);
  console.log(`    source_systems.ingestion_batch: ${s.rows.map((r) => `${r.batch_id}=${r.load_type}/${r.load_status}`).join(", ")}`);
  console.log(`    silver.ingestion_batch        : ${b.rows.map((r) => `${r.batch_id}=${r.load_status}`).join(", ") || "(empty)"}`);
};

await state("after loading Member 1 files 01-04");

console.log("\n  calling B2-CRM with is_retry = TRUE (what file 05 does first)");
try {
  await db.exec(`CALL silver.process_incremental_batch('B2-CRM', TRUE);`);
  console.log("  call returned without error");
} catch (error) {
  console.log(`  call raised: ${String(error.message).split("\n")[0].slice(0, 160)}`);
}
await state("after the B2-CRM call");

console.log("\n  calling B2-LEND with is_retry = FALSE (what file 06 does)");
try {
  await db.exec(`CALL silver.process_incremental_batch('B2-LEND', FALSE);`);
  console.log("  call returned without error");
} catch (error) {
  console.log(`  call raised: ${String(error.message).split("\n")[0].slice(0, 160)}`);
}
await state("after the B2-LEND call");

const raw = await db.query(
  `SELECT batch_id, count(*)::int AS n FROM bronze.raw_aml_screening GROUP BY batch_id ORDER BY batch_id`,
);
console.log(`\n  bronze.raw_aml_screening by batch: ${raw.rows.map((r) => `${r.batch_id}=${r.n}`).join(", ")}`);
