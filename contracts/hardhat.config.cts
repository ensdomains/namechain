import type { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-viem";
import "./tasks/esm_fix.cjs";

import("@ensdomains/hardhat-chai-matchers-viem");

const config = {
  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      evmVersion: "cancun",
      metadata: {
        useLiteralContent: true, // required for @ensdomains/hardhat-chai-matchers-viem/behaviour
      },
    },
  },
} satisfies HardhatUserConfig;

export default config;
