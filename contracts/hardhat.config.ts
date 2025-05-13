import fs from 'node:fs'
import type { HardhatUserConfig } from "hardhat/config";

import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatDeploy from "hardhat-deploy";

// Define the config object with the HardhatUserConfig interface
const config: HardhatUserConfig = {
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
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      evmVersion: "cancun",
      metadata: {
        useLiteralContent: true, // required for @ensdomains/hardhat-chai-matchers-viem/behaviour
      },
    },
    remappings: fs.readFileSync("./remappings.txt", "utf-8").split("\n").map(line => line.trim()).filter(line => line.length > 0),
  },
  paths: {
    sources: "./src",
    tests: "./test",
  },
  plugins: [HardhatViem, HardhatDeploy],
};

export default config;
