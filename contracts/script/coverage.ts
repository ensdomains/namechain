import { execSync } from "node:child_process";
import { mkdirSync, readdirSync, rmSync } from "node:fs";

const EXT = ".info";
const cwd = new URL("../coverage/", import.meta.url);

// find coverage files
const found = readdirSync(cwd).filter((x) => x.endsWith(EXT));
if (!found.length) {
  throw new Error("no coverage files, execute: bun run coverage");
}
console.table(found);

// clean filtered directory
const filteredDir = new URL(N(""), cwd);
rmSync(filteredDir, { recursive: true, force: true });
mkdirSync(filteredDir, { recursive: true });

// generate individual reports
for (const name of found) {
  execSync(
    `lcov --ignore-errors unused,unused --remove ${name} "lib/*" "*test*" "*mock*" --output-file ${N(name)}`,
    { cwd },
  );
}

// generate combined report
const name = `all${EXT}`;
execSync(
  `lcov --ignore-errors inconsistent,unused --rc branch_coverage=1 --add-tracefile "${N("*")}" --output-file ${N(name)}`,
  { cwd },
);

function N(name: string) {
  return `filtered/${name}`;
}
