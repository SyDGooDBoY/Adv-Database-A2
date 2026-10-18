// Watch the batch registry as each module loads, to find which step removes the
// B2 batches that Member 1 registers.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const here = dirname(fileURLToPath(import.meta.url));
const sqlRoot = join(here, "..", "..", "advanced-database-assignment2", "sql");
const db = new PGlite();

const DEFERRED = [/validation_tests|validation_demo/, /_run_/];
const files = (key) => {
  const dir = join(sqlRoot, key);
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((n) => n.endsWith(".sql"))
    .filter((n) => !DEFERRED.some((p) => p.test(n)))
    .sort();
};

const batches = async () => {
  const r = await db.query(`SELECT batch_id, load_status FROM silver.ingestion_batch ORDER BY batch_id`);
  return r.rows.map((x) => `${x.batch_id}=${x.load_status}`).join(" ") || "(empty)";
};

const step = async (label, path) => {
  try {
    await db.exec(readFileSync(path, "utf8"));
  } catch (error) {
    console.log(`    !! ${label}: ${String(error.message).split("\n")[0].slice(0, 110)}`);
  }
};

for (const name of files("00_shared_setup")) {
  if (Number.parseInt(name.slice(0, 2), 10) <= 49) {
    await step(name, join(sqlRoot, "00_shared_setup", name));
  }
}
console.log(`after shared setup        : ${await batches()}`);

// Member 1 loads itself, then report after every single file.
for (const name of files("module1_hongfei")) {
  await step(`hongfei/${name}`, join(sqlRoot, "module1_hongfei", name));
  console.log(`after hongfei/${name.padEnd(38)}: ${await batches()}`);
}

// Now the other modules, in the harness order, reporting after each file.
for (const key of ["module2_mina", "module3_kaijie", "module5_guanbo", "module4_dan", "module6_sunny"]) {
  for (const name of files(key)) {
    await step(`${key}/${name}`, join(sqlRoot, key, name));
    console.log(`after ${key}/${name.padEnd(44)}: ${await batches()}`);
  }
}
