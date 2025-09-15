import type { HardhatUserConfig } from "hardhat/config";

import HardhatChaiMatchersViemPlugin from "@ensdomains/hardhat-chai-matchers-viem";
import HardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

import HardhatStorageLayoutPlugin from "./plugins/storage-layout/index.ts";
import HardhatIgnoreWarningsPlugin from "./plugins/ignore-warnings/index.ts";

const config = {
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
      {
        version: "0.4.11",
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
  ],
} satisfies HardhatUserConfig;

export default config;
