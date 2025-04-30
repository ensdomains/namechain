import { configVariable, type HardhatUserConfig } from "hardhat/config";

import HardhatKeystore from "@nomicfoundation/hardhat-keystore";
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
      evmVersion: "cancun",
    },
    remappings: [
      "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
      "@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/",
      "@ens/contracts/=lib/ens-contracts/contracts/",
      "@ensdomains/buffer/=lib/buffer/",
      "@unruggable/gateways/=lib/unruggable-gateways/",
      "@ensdomains/verifiable-factory/=lib/verifiable-factory/src/",
      "forge-std/=lib/forge-std/src/",
    ],
  },
  paths: {
    sources: "./src",
  },
  plugins: [HardhatViem, HardhatDeploy, HardhatKeystore],
} satisfies HardhatUserConfig;

export default config;
