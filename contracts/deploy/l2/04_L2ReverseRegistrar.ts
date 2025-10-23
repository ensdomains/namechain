import { evmChainIdToCoinType } from "@ensdomains/address-encoder/utils";
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer }, network }) => {
    const chainId = network.chain.id;
    const coinType = evmChainIdToCoinType(chainId);

    await deploy("L2ReverseRegistrar", {
      account: deployer,
      artifact: artifacts.L2ReverseRegistrar,
      args: [coinType],
    });
  },
  {
    tags: ["L2ReverseRegistrar", "l2"],
  },
);
