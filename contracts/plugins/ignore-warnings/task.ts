import { type TaskOverrideActionFunction } from "hardhat/types/tasks";

const action: TaskOverrideActionFunction = async (task, hre, runSuper) => {
  const fn = hre.userConfig.shouldIgnoreWarnings;
  if (!fn) return runSuper(task);
  const {stderr} = process;
  const write0 = stderr.write as any;
  stderr.write = (...a: any[]) => {
    if (typeof a[0] === 'string') {
      // it appears all hardhat compile errors are strings
      const msg = a[0].replaceAll(/[\u001b][^m]+m/g, '').trim(); // remove ansi coloring
      const match = msg.match(/^Warning: .*?--> (.*?)(?::\d+:\d+|$)/ms);
      if (match && fn(match[1], msg)) {
        (a[2] as (err?: Error) => void | undefined)?.(); // call optional callback
        return true; // fake continue
      }
    } 
    return write0.call(stderr, ...a); // original behavior
  };
  try {
    return await runSuper(task);
  } finally {
    stderr.write = write0;
  }
};

export default action;
