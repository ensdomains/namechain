import { program } from "@commander-js/extra-typings";
import { $ } from "bun";

const chainData = {
  sepolia: {
    chainType: 1,
    chainId: 11155111,
    rpcUrl: process.env.SEPOLIA_RPC_URL,
  },
  mainnet: {
    chainType: 1,
    chainId: 1,
    rpcUrl: process.env.MAINNET_RPC_URL,
  },
  "local-l1": {
    chainType: 1,
    chainId: 31337,
    rpcUrl: process.env.LOCAL_L1_RPC_URL,
  },
  "local-l2": {
    chainType: 2,
    chainId: 33333,
    rpcUrl: process.env.LOCAL_L2_RPC_URL,
  },
} as const;

// forge script --chain sepolia script/Counter.s.sol:CounterScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv --interactives 1

program
  .argument("<chain>", "The chain to run the script on")
  .argument("<script>", "The script to run")
  .option("--use-shared", "Use the shared script directory")
  .action(async (chain, script, { useShared }) => {
    if (chain === "local" && script === "all") {
      console.log("Deploying all contracts to local chains...");
      await $`bun run deploy local-l1 L1`;
      await $`bun run deploy local-l2 L2`;
      process.exit(0);
    }

    const selectedChain = chainData[chain as keyof typeof chainData];
    if (!selectedChain) {
      console.error(`Chain ${chain} not found`);
      process.exit(1);
    }

    const scriptParentDir = (() => {
      if (useShared) return "./script/shared";
      return selectedChain.chainType === 1 ? "./script/l1" : "./script/l2";
    })();

    const scriptPath = `${scriptParentDir}/${script}.s.sol`;

    await $`CHAIN_TYPE=${selectedChain.chainType} forge script --chain ${
      selectedChain.chainId
    } ${scriptPath} --rpc-url ${selectedChain.rpcUrl} --broadcast ${
      chain.startsWith("local") ? "" : "--verify --interactives 1"
    } -vvvv`;
  });

program.parse();
