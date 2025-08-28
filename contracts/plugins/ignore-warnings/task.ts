import type { TaskOverrideActionFunction } from "hardhat/types/tasks";

const action: TaskOverrideActionFunction = async (task, hre, runSuper) => {
  const should = hre.userConfig.shouldIgnoreWarnings;
  if (!should) return runSuper(task);
  const { stderr } = process;
  const write0 = stderr.write as any;
  let ignored = 0;
  let compiled = false;
  stderr.write = (...a: any[]) => {
    compiled = true;
    if (typeof a[0] === "string") {
      // 20250719: it appears all hardhat compile errors are strings
      const msg = a[0].replaceAll(/\x1b[^m]+m/g, "").trim(); // remove ansi coloring
      let match = msg.match(/^Warning: .*?--> (.*?)(?::\d+:\d+|$)/ms);
      if (match && should(match[1], msg)) {
        ++ignored;
        a[2]?.(); // call callback
        return true; // fake continue
      }
      // rewrite disgusting code size errors
      if (
        (match = msg.match(
          /^Warning: Contract (code|initcode) size is (\d+) bytes and exceeds (\d+) bytes \(a limit introduced in ([^\)]+)\).*?--> ([^:]+)/ms,
        ))
      ) {
        const [, type, size, max, , file] = match;
        console.log(
          `${ansi(33, `Size[${type.slice(0, 4)}]:`)} ${ansi(31, `${size} > ${max}`)} ${file}`,
        );
        a[2]?.();
        return true;
      }
    }
    return write0.apply(stderr, a); // original behavior
  };
  try {
    return await runSuper(task);
  } finally {
    stderr.write = write0;
    if (compiled) {
      console.error(
        `>>> ${ansi(33, "Ignored Warnings:")} ${ansi(31, ignored)} <<<`,
      );
    }
  }
};

function ansi(c: any, s: any) {
  return `\x1b[${c}m${s}\x1b[0m`;
}

export default action;
