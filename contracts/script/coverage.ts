import { execSync } from "node:child_process";
import { readdirSync, rmSync } from "node:fs";

const SUFFIX = ".lcov";
const PREFIX = "filtered-";
const DIR = "./coverage/";

const rootDir = new URL("../", import.meta.url);
const coverageDir = new URL(DIR, rootDir);

// find coverage files
const found: string[] = [];
for (const name of readdirSync(coverageDir)) {
  if (name.startsWith(PREFIX)) {
    rmSync(new URL(name, coverageDir)); // clean filtered files
  } else if (name.endsWith(SUFFIX)) {
    found.push(name);
  }
}
if (!found.length) {
  throw new Error("no coverage files, execute: bun run coverage");
}
console.table(found);

// generate individual reports
for (const name of found) {
  execSync(
    `lcov --ignore-errors unused,unused --remove ${DIR}${name} "lib/*" "*test*" "*mock*" --output-file ${DIR}${PREFIX}${name}`,
    { cwd: rootDir },
  );
  createReport(name);
}

// generate combined report
const name = `all${SUFFIX}`;
execSync(
  `lcov --ignore-errors inconsistent,unused --rc branch_coverage=1 --add-tracefile "${DIR}${PREFIX}*${SUFFIX}" --output-file ${DIR}${PREFIX}${name}`,
  { cwd: rootDir },
);
createReport(name);

function createReport(name: string) {
  const title = name.replace(SUFFIX, "");
  execSync(
    `genhtml ${DIR}${PREFIX}${name} --flat --output-directory ${DIR}reports/${title}`,
    { cwd: rootDir },
  );
  console.log(`Wrote Report: ${title}`);
}
