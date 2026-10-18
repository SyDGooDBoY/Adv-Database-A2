// Run every check in order and stop at the first failure.
//
// Order matters: the static parse is the fastest way to catch a syntax error, so
// it runs before the suites that take seconds. Each child writes to this
// process's streams, so the output appears live in the terminal.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const moduleDir = join(here, "..", "..", "advanced-database-assignment2", "sql", "module5_guanbo");

// python is used for two static checks. It is resolved explicitly, because a
// bundled interpreter is often not on PATH, and a quoted absolute path with
// spaces must not be handed to a shell. Set the PYTHON environment variable to
// override, otherwise the usual names are probed.
function resolve(explicit, ...candidates) {
  if (explicit && existsSync(explicit)) return { command: explicit, shell: false };
  for (const candidate of candidates) {
    const probe = spawnSync("where", [candidate], { encoding: "utf8", shell: true });
    const found = (probe.stdout ?? "").split(/\r?\n/).find((line) => line.trim());
    if (found) return { command: found.trim(), shell: false };
  }
  return { command: candidates[0], shell: true };
}

const python = resolve(process.env.PYTHON, "python", "python3", "py");
const node = resolve(process.execPath, "node");

const CHECKS = [
  {
    name: "Static parse of every module script",
    ...python,
    args: [join(moduleDir, "validate_syntax.py")],
    cwd: moduleDir,
    hint: "If python was not found, set the PYTHON environment variable to its full path.",
  },
  {
    name: "Dead code and dangling references",
    ...python,
    args: ["analyse.py"],
    cwd: here,
  },
  {
    name: "Module test - this module on its own",
    ...node,
    args: ["verify.mjs"],
    cwd: here,
    hint: "Expected: ALL CHECKS PASSED",
  },
  {
    name: "Integration test - all six members together",
    ...node,
    args: ["integration.mjs"],
    cwd: here,
    hint: "Expected: 0 failed",
  },
];

if (!existsSync(join(here, "node_modules"))) {
  console.log("node_modules is missing. Run the install task first:");
  console.log("  pnpm install");
  process.exit(1);
}

const failed = [];
for (const [index, check] of CHECKS.entries()) {
  console.log(`\n${"#".repeat(74)}`);
  console.log(`# ${index + 1}/${CHECKS.length}  ${check.name}`);
  console.log(`${"#".repeat(74)}`);

  // shell comes from the resolved entry: false for an explicit path (so a path
  // containing spaces stays one argument), true only when the name must be
  // resolved through PATH.
  const result = spawnSync(check.command, check.args, {
    cwd: check.cwd,
    stdio: "inherit",
    shell: check.shell,
  });

  const ok = result.status === 0;
  console.log(`\n>>> ${ok ? "PASSED" : "FAILED"}: ${check.name}`);
  if (!ok) {
    if (check.hint) console.log(`    ${check.hint}`);
    if (result.error) console.log(`    ${result.error.message}`);
    failed.push(check.name);
    break; // stop at the first failure: later checks assume the earlier ones passed
  }
}

console.log(`\n${"=".repeat(74)}`);
if (failed.length === 0) {
  console.log(`ALL ${CHECKS.length} CHECKS PASSED`);
  process.exit(0);
}
console.log(`STOPPED AT: ${failed[0]}`);
process.exit(1);
