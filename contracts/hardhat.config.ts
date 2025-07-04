import { configVariable, type HardhatUserConfig } from "hardhat/config";

import HardhatChaiMatchersViemPlugin from "@ensdomains/hardhat-chai-matchers-viem";
import HardhatKeystore from "@nomicfoundation/hardhat-keystore";
import HardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

import HardhatStorageLayoutPlugin from "./plugins/storage-layout/index.ts";

const realAccounts = [
  configVariable("DEPLOYER_KEY"),
  configVariable("OWNER_KEY"),
];

const config = {
  networks: {
    "l1-local": {
      url: "http://127.0.0.1:8545",
      type: "http",
      chainId: 31337,
    },
    "l2-local": {
      url: "http://127.0.0.1:8546",
      type: "http",
      chainId: 31338,
    },
    mainnet: {
      url: configVariable("MAINNET_RPC_URL"),
      type: "http",
      accounts: realAccounts,
    },
    sepolia: {
      url: configVariable("SEPOLIA_RPC_URL"),
      type: "http",
      accounts: realAccounts,
    },
    holesky: {
      url: configVariable("HOLESKY_RPC_URL"),
      type: "http",
      accounts: realAccounts,
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
      {
        version: "0.4.11",
      },
    ],
  },
  paths: {
    sources: {
      solidity: [
        "./src",
        "./lib/verifiable-factory/src",
        "./lib/ens-contracts/contracts/",
        "./lib/openzeppelin-contracts/contracts/utils/introspection/",
      ],
    },
  },
  plugins: [
    HardhatNetworkHelpersPlugin,
    HardhatChaiMatchersViemPlugin,
    HardhatViem,
    HardhatKeystore,
    HardhatStorageLayoutPlugin,
    HardhatDeploy,
  ],
} satisfies HardhatUserConfig;

export default config;
