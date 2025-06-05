import type { NetworkConnection } from "hardhat/types/network";

type RPCCounter = {
  count: number;
  reset(): number;
};

export function injectRPCCounter<C extends NetworkConnection>(
  chain: C extends RPCCounter ? never : C,
): C & RPCCounter {
  const impl = Object.assign(chain, {
    count: 0,
    reset() {
      const { count } = this;
      this.count = 0;
      return count;
    },
  });
  const old = chain.provider.request.bind(chain.provider);
  impl.provider.request = async (...a: Parameters<typeof old>) => {
    impl.count++;
    return old(...a);
  };
  return impl;
}

// export function createFixture<T>(
//   networkConnection: NetworkConnection<DefaultChainType>,
//   fixture: (n: NetworkConnection<DefaultChainType>) => Fixture<T>,
// ) {
//   const initialisedFixture = fixture(networkConnection);
//   return async () =>
//     networkConnection.networkHelpers.loadFixture(initialisedFixture);
// }
