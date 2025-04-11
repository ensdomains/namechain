import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

// `$ bun script/sol-versions.ts`
// prints the semver for every Solidity file

type Contract = { spec: string; file: string };

const specs: string[] = [];

function uniqueColor(spec: string) {
	let i = specs.indexOf(spec);
	if (i < 0) {
		i = specs.length;
		specs.push(spec);
	}
	return `\x1b[${91 + (i % 6)}m${spec}\x1b[0m`;
}

find(fileURLToPath(new URL("../src/", import.meta.url)))
	.sort(
		(a, b) => a.spec.localeCompare(b.spec) || a.file.localeCompare(b.file)
	)
	.forEach((x) => console.log(uniqueColor(x.spec.padEnd(10)), x.file));

function find(dir: string, found: Contract[] = [], skip = dir.length) {
	for (const x of readdirSync(dir, { withFileTypes: true })) {
		const path = join(dir, x.name);
		if (x.isDirectory()) {
			find(path, found, skip);
		} else if (x.name.endsWith(".sol")) {
			const code = readFileSync(path, { encoding: "utf-8" });
			const match = code.match(/^pragma solidity (.*?);/m);
			if (!match) throw new Error(`expected pragma: ${path}`);
			found.push({
				spec: match[1].trim(),
				file: path.slice(skip),
			});
		}
	}
	return found;
}
