import hre from "hardhat";
import { addStatementCoverageInstrumentation } from "@nomicfoundation/edr";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { toHex } from "viem";

// https://github.com/NomicFoundation/hardhat/blob/main/v-next/hardhat/src/internal/builtin-plugins/coverage/hook-handlers/hre.ts
// https://github.com/NomicFoundation/hardhat/blob/main/v-next/hardhat/src/internal/builtin-plugins/coverage/hook-handlers/solidity.ts

// hooks need to be registered super early
const activeTags: Set<string[]> = new Set();
hre.hooks.registerHandlers("network", {
  async onCoverageData(_, tags) {
    for (const x of activeTags) {
      x.push(...tags);
    }
  },
});

export function injectCoverage() {
  const connect0 = hre.network.connect.bind(hre.network);
  hre.network.connect = async (params: unknown) => {
    if (params) throw new Error("expected just connect()");
    return connect0({ override: { allowUnlimitedContractSize: true } });
  };
}

export function recordCoverage(testName: string) {
  const tags: string[] = [];
  activeTags.add(tags);
  return async () => {
    activeTags.delete(tags);
    if (!tags.length) return;

    const rootDir = new URL("../../", import.meta.url);
    const artifactStr = await readFile(
      new URL("generated/artifacts.ts", rootDir),
      { encoding: "utf8" },
    );

    const hardhatLibrary = artifactStr.match(
      /__hardhat_coverage_library_[a-f0-9-]+\.sol/,
    )?.[0];
    if (!hardhatLibrary) {
      throw new Error("expected hardhat coverage library");
    }

    const rawArtifacts = JSON.parse(
      artifactStr.slice(
        artifactStr.indexOf("{"),
        artifactStr.lastIndexOf("}") + 1,
      ),
    ) as Record<
      string,
      {
        sourceName: string;
        inputSourceName: string;
        metadata: string;
      }
    >;

    type Location = {
      tag: string;
      file: string;
      line0: number;
      line1: number;
      count: number;
    };
    const tagMap = new Map<string, Location>();
    const fileMap = new Map<string, Location[]>();
    for (const rawArtifact of Object.values(rawArtifacts)) {
      const code = await readFile(new URL(rawArtifact.sourceName, rootDir), {
        encoding: "utf8",
      });
      const rawMetadata = JSON.parse(rawArtifact.metadata) as {
        compiler: { version: string };
      };
      const { metadata } = addStatementCoverageInstrumentation(
        code,
        rawArtifact.inputSourceName, // "project/..."
        rawMetadata.compiler.version.replace(/\+.*$/, ""), // "0.8.25"+commit.b61c2a9 => "0.8.25"
        hardhatLibrary,
      );

      // generate line numbers
      const lineNumbers: number[] = [];
      for (let i = 0, n = 1; i < code.length; i++) {
        lineNumbers[i] = n;
        if (code[i] == "\n") n++;
      }

      // convert statements to locations
      const locs: Location[] = metadata
        .filter((x) => x.kind === "statement")
        .map((x) => ({
          tag: toHex(x.tag).slice(2),
          file: rawArtifact.sourceName,
          line0: lineNumbers[x.startUtf16],
          line1: lineNumbers[x.endUtf16 - 1],
          count: 0,
        }));

      // save locations
      const file = rawArtifact.sourceName;
      fileMap.set(file, locs);
      for (const loc of locs) {
        tagMap.set(loc.tag, loc);
      }
    }

    // count location hits
    for (const tag of tags) {
      const loc = tagMap.get(tag);
      if (loc) loc.count++;
    }

    // construct lcov file
    // https://github.com/linux-test-project/lcov/blob/df03ba434eee724bfc2b27716f794d0122951404/man/geninfo.1#L1409
    // https://github.com/NomicFoundation/hardhat/blob/main/v-next/hardhat/src/internal/builtin-plugins/coverage/coverage-manager.ts#L275

    let lcov = `TN:${testName}\n`;

    for (const [file, locs] of fileMap) {
      //if (!locs.find(x => x.count > 0)) continue;

      lcov += `SF:${file}\n`;

      // for (const loc of locs) {
      //   for (let i = loc.line0; i <= loc.line1; i++) {
      //     lcov += `BRDA:${i},0,${loc.tag},${loc.count || "-"}\n`;
      //   }
      // }
      // lcov += `BRH:${executedBranchesCount}\n`;
      // lcov += `BRF:${branchExecutionCounts.size}\n`;

      const lineCounts: number[] = [];
      for (const loc of locs) {
        for (let i = loc.line0; i <= loc.line1; i++) {
          lineCounts[i] = (lineCounts[i] ?? 0) + loc.count;
        }
      }
      for (const [line, count] of Object.entries(lineCounts)) {
        lcov += `DA:${line},${count}\n`;
      }
      // lcov += `LH:${locs.reduce((a, x) => a + (x.count ? 1 : 0), 0)}\n`;
      // lcov += `LF:${locs.length}\n`;

      lcov += "end_of_record\n";
    }

    // write file
    const outDir = new URL("coverage/", rootDir);
    await mkdir(outDir, { recursive: true });
    await writeFile(new URL(`${testName}.info`, outDir), lcov);
    console.log(`Wrote Coverage: ${testName}`);
  };
}
