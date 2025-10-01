import { $ } from "bun";
import { readdirSync } from "node:fs";
import { basename, join } from "node:path";

const SUFFIX = ".lcov";
const PREFIX = "filtered-";
const DIR = "./coverage/";

const rootDir = new URL("../", import.meta.url);
const coverageDir = new URL(DIR, rootDir);

if (!process.env.CC_TOKEN) throw new Error("CC_TOKEN is not set");

// check if codecov-cli is installed
const codecov = await $`which codecov`.nothrow().quiet();
if (codecov.exitCode !== 0) {
  // only install on CI
  if (!process.env.CI) throw new Error("Please install codecov-cli");

  // install
  const installUrl = "https://cli.codecov.io/latest/linux/codecov";
  await $`curl -Os ${installUrl}`;

  // integrity check
  await $`curl https://keybase.io/codecovsecurity/pgp_keys.asc | gpg --no-default-keyring --keyring trustedkeys.gpg --import`;
  await $`curl -Os ${installUrl}.SHA256SUM`;
  await $`curl -Os ${installUrl}.SHA256SUM.sig`;

  await $`gpgv codecov.SHA256SUM.sig codecov.SHA256SUM`;
  await $`shasum -a 256 -c codecov.SHA256SUM`;

  await $`chmod +x codecov`;
}

const baseCmd = [
  "./codecov",
  "upload-coverage",
  `-t ${process.env.CC_TOKEN}`,
  ...(process.env.CC_GIT_SERVICE
    ? [`--git-service ${process.env.CC_GIT_SERVICE}`]
    : []),
  ...(process.env.CC_SHA ? [`--sha ${process.env.CC_SHA}`] : []),
];

const coverageFiles = readdirSync(coverageDir).filter(
  (file) => file.startsWith(PREFIX) && file.endsWith(SUFFIX),
);

for (const file of coverageFiles) {
  const flagName = basename(file, SUFFIX).replace(PREFIX, "");
  const filePath = join(coverageDir.pathname, file);
  await $`${baseCmd.join(" ")} --flag ${flagName} --file ${filePath}`;
}
