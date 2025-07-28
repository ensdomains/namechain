/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { parseEther } from "viem";

const BASE_PRICE = parseEther("0.01");
const PREMIUM_PRICE = parseEther("0.005");

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("PriceOracle", {
      account: deployer,
      artifact: artifacts.MockPriceOracle,
      args: [BASE_PRICE, PREMIUM_PRICE],
    });
  },
  // finally you can pass tags and dependencies
  { tags: ["PriceOracle", "registry", "l2"] },
);
