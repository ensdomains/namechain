import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("StableTokenPriceOracle", {
      account: deployer,
      artifact: artifacts.StableTokenPriceOracle,
    });
  },
  {
    tags: ["StableTokenPriceOracle", "l2"],
  },
);
