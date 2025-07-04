import { type TaskOverrideActionFunction } from "hardhat/types/tasks";

const action: TaskOverrideActionFunction = async (task, hre, runSuper) => {
  const fn = hre.userConfig.sourceFilter;
  if (fn) {
    const old = hre.solidity.getRootFilePaths.bind(hre.solidity);
    hre.solidity.getRootFilePaths = async () => (await old()).filter(fn);
  }
  return runSuper(task);
};

export default action;
