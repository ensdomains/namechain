import type { NetworkConnection } from "hardhat/types/network";

export function injectRPCCounter<C extends NetworkConnection>(chain: C) {
  const impl = {
    count: 0,
    reset() {
      const { count } = this;
      this.count = 0;
      return count;
    },
  };
  const old = chain.provider.request.bind(chain.provider);
  chain.provider.request = async (...a: Parameters<typeof old>) => {
    impl.count++;
    return old(...a);
  };
  return Object.assign(chain, impl);
}

// export function createFixture<T>(
//   networkConnection: NetworkConnection<DefaultChainType>,
//   fixture: (n: NetworkConnection<DefaultChainType>) => Fixture<T>,
// ) {
//   const initialisedFixture = fixture(networkConnection);
//   return async () =>
//     networkConnection.networkHelpers.loadFixture(initialisedFixture);
// }
