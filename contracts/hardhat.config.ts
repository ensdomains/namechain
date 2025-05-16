import { configVariable, type HardhatUserConfig } from "hardhat/config";
import fs from 'node:fs';

import HardhatChaiMatchersViemPlugin from "@ensdomains/hardhat-chai-matchers-viem";
import HardhatKeystore from "@nomicfoundation/hardhat-keystore";
import HardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

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
      url: "http://127.0.0.1:9545",
      type: "http",
      chainId: 33333,
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
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      evmVersion: "cancun",
    },
    remappings: fs.readFileSync("./remappings.txt", "utf-8").split("\n").map(line => line.trim()).filter(line => line.length > 0),
  },
  paths: {
    sources: [
      "./src",
      "./lib/verifiable-factory/src",
      "./lib/ens-contracts/contracts/resolvers/profiles/",
      "./lib/openzeppelin-contracts/contracts/utils/introspection/",
    ],
  },
  plugins: [
    HardhatNetworkHelpersPlugin,
    HardhatChaiMatchersViemPlugin,
    HardhatViem,
    HardhatDeploy,
    HardhatKeystore,
  ],
} satisfies HardhatUserConfig;

export default config;
