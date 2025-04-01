/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

const MIN_COMMITMENT_AGE = 60n; // 1 minute
const MAX_COMMITMENT_AGE = 86400n; // 1 day

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const registry = get<(typeof artifacts.ETHRegistry)["abi"]>("ETHRegistry");
    const priceOracle =
      get<(typeof artifacts.MockPriceOracle)["abi"]>("PriceOracle");

    await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        registry.address,
        priceOracle.address,
        MIN_COMMITMENT_AGE,
        MAX_COMMITMENT_AGE,
      ],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["ETHRegistrar", "registry", "l2"],
    dependencies: ["ETHRegistry", "PriceOracle"],
  }
);
