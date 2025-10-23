import type { Address, Chain } from "viem";

export type RockethL1Arguments = {
  l2Deploy: {
    deployments: Record<string, { address: Address }>;
    network: {
      chain: Chain;
    };
  };
  verifierAddress: Address;
  verifierGateways: string[];
};

export type RockethArguments = RockethL1Arguments | undefined;
