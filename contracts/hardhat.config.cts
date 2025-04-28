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
  networks: {
    local: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
      },
    }
  },
} satisfies HardhatUserConfig;

export default config;
