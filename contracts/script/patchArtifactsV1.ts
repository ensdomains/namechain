import { readFile, writeFile, mkdir } from "node:fs/promises";

export async function patchArtifactsV1() {
  const code = await readFile(
    new URL("../generated/artifacts.ts", import.meta.url),
    { encoding: "utf8" },
  );

  // extract the artifact data
  const prefix = code.indexOf("{");
  if (prefix === -1) throw new Error("expected prefix");
  const suffix = code.lastIndexOf("}") + 1;
  if (!suffix) throw new Error("expected suffix");

  // replace any contract collision with the original version
  const json = JSON.parse(code.slice(prefix, suffix));
  for (const [key, value] of Object.entries(json)) {
    if (key.startsWith("lib/ens-contracts/")) {
      json[value.contractName] = value;
    }
  }

  // rebuild the artifact file
  const newCode =
    code.slice(0, prefix) + JSON.stringify(json) + code.slice(suffix);
  const outDir = new URL("../lib/ens-contracts/generated/", import.meta.url);
  await mkdir(outDir, { recursive: true });
  await writeFile(new URL("./artifacts.ts", outDir), newCode);
}
