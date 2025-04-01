import type { HardhatUserConfig } from "hardhat/config";

import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

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
      "verifiable-factory/=lib/verifiable-factory/src/",
      "forge-std/=lib/forge-std/src/",
    ],
  },
  paths: {
    sources: "./src",
  },
  plugins: [HardhatViem, HardhatDeploy],
} satisfies HardhatUserConfig;

export default config;
