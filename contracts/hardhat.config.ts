import { configVariable, type HardhatUserConfig } from "hardhat/config";

import HardhatChaiMatchersViemPlugin from "@ensdomains/hardhat-chai-matchers-viem";
import HardhatKeystore from "@nomicfoundation/hardhat-keystore";
import HardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

import HardhatIgnoreWarningsPlugin from "./plugins/ignore-warnings/index.ts";
import HardhatStorageLayoutPlugin from "./plugins/storage-layout/index.ts";

const config = {
  networks: {
    sepoliaFresh: {
      type: "http",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("DEPLOYER_KEY")],
      chainId: 11155111,
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.25",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
          evmVersion: "cancun",
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
    ],
  },
  paths: {
    sources: {
      solidity: [
        "./src/",
        "./lib/verifiable-factory/src/",
        "./lib/ens-contracts/contracts/",
        "./lib/openzeppelin-contracts/contracts/utils/introspection/",
      ],
    },
  },
  shouldIgnoreWarnings: (path) => {
    return (
      path.startsWith("./lib/ens-contracts/") ||
      path.startsWith("./lib/solsha1/")
    );
  },
  plugins: [
    HardhatNetworkHelpersPlugin,
    HardhatChaiMatchersViemPlugin,
    HardhatViem,
    HardhatStorageLayoutPlugin,
    HardhatIgnoreWarningsPlugin,
    HardhatDeploy,
    HardhatKeystore,
  ],
} satisfies HardhatUserConfig;

export default config;
