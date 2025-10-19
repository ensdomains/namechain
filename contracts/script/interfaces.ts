import { isHex } from "viem";
import { rmSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { execSync } from "node:child_process";

// $ bun interfaces                  # all
// $ bun interfaces Ens              # by name (ignores case)
// $ bun interfaces 0x9061b923       # by selector
// $ bun interfaces Ens 0x9061b923   # mixture of names/selectors
// $ bun interfaces ... --json       # export as JSON

const ifaces = findAllInterfaces();

const UNKNOWN = "???";

let output: (x: any) => void = console.table;
const qs = process.argv.slice(2).filter((x) => {
  if (x === "--json") {
    output = (x) => {
      console.log();
      console.log(JSON.stringify(x, null, "  "));
    };
  } else {
    return true;
  }
});
if (qs.length) {
  output(
    qs.map((q) => {
      if (isHex(q) && q.length === 10) {
        return (
          ifaces.find((x) => same(x.interfaceId, q)) ?? {
            interfaceId: q,
            name: UNKNOWN,
          }
        );
      } else {
        return (
          ifaces.find((x) => same(x.name, q)) ?? {
            interfaceId: UNKNOWN,
            name: q,
          }
        );
      }
    }),
  );
} else {
  output(ifaces);
}

function same(a: string, b: string) {
  return !a.localeCompare(b, undefined, { sensitivity: "base" });
}

function findAllInterfaces() {
  type Interface = {
    interfaceId: string;
    name: string;
    file: string;
  };
  const ifaces: Interface[] = [];
  const rootDir = new URL("../", import.meta.url);
  for (const x of readdirSync(new URL("./out/", rootDir), {
    withFileTypes: true,
    recursive: true,
  })) {
    if (!x.isFile()) continue;
    if (x.parentPath.endsWith("build-info")) continue;
    const artifact = JSON.parse(
      readFileSync(join(x.parentPath, x.name), "utf8"),
    ) as {
      bytecode: { object: string };
      metadata: {
        settings: { compilationTarget: Record<string, string> };
      };
    };
    if (artifact.bytecode.object !== "0x") continue; // is contract
    const [[file, name]] = Object.entries(
      artifact.metadata.settings.compilationTarget,
    );
    let code: string;
    try {
      code = readFileSync(new URL(file, rootDir), "utf8");
    } catch (err) {
      continue;
    }
    const match = code.match(new RegExp(`interface\\s+${name}\\s+`, "m"));
    if (!match) continue; // is abstract contract
    ifaces.push({ interfaceId: "", name, file });
  }

  const testFile = "./test/InterfacePrinter.sol";
  try {
    writeFileSync(
      new URL(testFile, rootDir),
      `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
${ifaces.map((x, i) => `import {${x.name} as I${i}} from "${x.file}";`).join("\n")}
import {console} from "forge-std/console.sol";
contract InterfacePrinter {
  function test_a() external pure {
    ${ifaces.map((_, i) => `console.logBytes4(type(I${i}).interfaceId);`).join("\n")}
  }
}`,
    );
    const output = execSync(`forge test --no-cache ${testFile} -vv`, {
      encoding: "utf8",
    });
    const ids = Array.from(output.matchAll(/^  0x[0-9a-f]{8}$/gm), (x) =>
      x[0].trim(),
    );
    if (ids.length !== ifaces.length) throw new Error("length mismatch");
    ids.forEach((x, i) => (ifaces[i].interfaceId = x));
  } finally {
    rmSync(testFile, { force: true });
  }
  return ifaces
    .filter((x) => parseInt(x.interfaceId))
    .sort((a, b) => a.file.localeCompare(b.file));
}
