/// Deploy mock ERC20 tokens for L2 deployment
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    // Use our local MockERC20 contract
    const MockERC20 = artifacts["test/mocks/MockERC20.sol/MockERC20"];

    const mockUSDC = await deploy("MockUSDC", {
      account: deployer,
      artifact: MockERC20,
      args: ["USDC", 6, hcaFactory.address],
    });

    const mockDAI = await deploy("MockDAI", {
      account: deployer,
      artifact: MockERC20,
      args: ["DAI", 18, hcaFactory.address],
    });
  },
  {
    tags: ["MockTokens", "mocks", "l2"],
    dependencies: ["HCAFactory"],
  },
);
