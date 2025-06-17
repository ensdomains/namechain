import type { NetworkConnection } from "hardhat/types/network";

type RPCCounter = {
  counts: Record<string, number>;
};

export function injectRPCCounter<C extends NetworkConnection>(
  chain: Exclude<C, RPCCounter>,
): C & RPCCounter {
  const impl = Object.assign(chain, {
    counts: {},
  } as RPCCounter);
  const old = chain.provider.request.bind(chain.provider);
  impl.provider.request = async (...a: Parameters<typeof old>) => {
    const { method } = a[0];
    impl.counts[method] = (impl.counts[method] ?? 0) + 1;
    return old(...a);
  };
  return impl;
}

export async function getRawArtifact<N extends keyof typeof A>(name: N) {
  const { default: A } = await import("../../generated/artifacts.js");
  return A[name];
}

// export function createFixture<T>(
//   networkConnection: NetworkConnection<DefaultChainType>,
//   fixture: (n: NetworkConnection<DefaultChainType>) => Fixture<T>,
// ) {
//   const initialisedFixture = fixture(networkConnection);
//   return async () =>
//     networkConnection.networkHelpers.loadFixture(initialisedFixture);
// }
