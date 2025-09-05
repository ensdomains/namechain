/// Deploy mock ERC20 tokens for L2 deployment
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy,  namedAccounts: { deployer } }) => {
    // Use our local MockERC20 contract
    const MockERC20 = artifacts["src/mocks/MockERC20.sol/MockERC20"];

    const mockUSDC = await deploy("MockUSDC", {
      account: deployer,
      artifact: MockERC20,
      args: ["USDC", 6],
    });

    const mockDAI = await deploy("MockDAI", {
      account: deployer,
      artifact: MockERC20,
      args: ["DAI", 18],
    });

    // console.table(
    //   await Promise.all(
    //     [mockUSDC, mockDAI].map(async (x) => {
    //       const [symbol, decimals] = await Promise.all([
    //         read(x, { functionName: "symbol" }),
    //         read(x, { functionName: "decimals" }),
    //       ]);
    //       return { symbol, decimals, address: x.address };
    //     }),
    //   ),
    // );
  },
  {
    tags: ["MockTokens", "mocks", "l2"],
  },
);
