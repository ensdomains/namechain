/// Deploy mock ERC20 tokens for L2 deployment
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    // Use our local MockERC20 contract
    const MockERC20 = artifacts["src/mocks/MockERC20.sol/MockERC20"];

    // Deploy MockUSDC (6 decimals)
    const mockUSDC = await deploy("MockUSDC", {
      account: deployer,
      artifact: MockERC20,
      args: ["USD Coin", "USDC", 6],
    });

    // Deploy MockDAI (18 decimals)
    const mockDAI = await deploy("MockDAI", {
      account: deployer,
      artifact: MockERC20,
      args: ["Dai Stablecoin", "DAI", 18],
    });

    console.log(`✅ Mock tokens deployed:`);
    console.log(`   - MockUSDC (6 decimals): ${mockUSDC.address}`);
    console.log(`   - MockDAI (18 decimals): ${mockDAI.address}`);
  },
  {
    tags: ["MockTokens", "tokens", "l2", "mock"],
    dependencies: [],
  },
);
