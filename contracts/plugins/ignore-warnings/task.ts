import type { TaskOverrideActionFunction } from "hardhat/types/tasks";

const action: TaskOverrideActionFunction = async (task, hre, runSuper) => {
  const fn = hre.userConfig.shouldIgnoreWarnings;
  if (!fn) return runSuper(task);
  const { stderr } = process;
  const write0 = stderr.write as any;
  let ignored = 0;
  stderr.write = (...a: any[]) => {
    if (typeof a[0] === "string") {
      // it appears all hardhat compile errors are strings
      const msg = a[0].replaceAll(/[\u001b][^m]+m/g, "").trim(); // remove ansi coloring
      const match = msg.match(/^Warning: .*?--> (.*?)(?::\d+:\d+|$)/ms);
      if (match && fn(match[1], msg)) {
        ++ignored;
        (a[2] as (err?: Error) => void | undefined)?.(); // call optional callback
        return true; // fake continue
      }
    }
    return write0.apply(stderr, a); // original behavior
  };
  try {
    return await runSuper(task);
  } finally {
    stderr.write = write0;
    console.error(
      `>>> ${ansi(33, "Ignored Warnings:")} ${ansi(31, ignored)} <<<`,
    );
  }
};

function ansi(c: any, s: any) {
  return `\x1b[${c}m${s}\x1b[0m`;
}

export default action;
