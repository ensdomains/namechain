import type { Address } from "viem";

export type RockethL1Arguments = {
  l2Deploy: {
    deployments: Record<string, { address: Address }>;
  };
  verifierAddress: Address;
};

export type RockethArguments = RockethL1Arguments | undefined;
