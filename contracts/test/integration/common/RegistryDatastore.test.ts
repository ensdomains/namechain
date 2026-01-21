import { BrowserProvider } from "ethers/providers";
import hre from "hardhat";
import {
  type AbiParameter,
  type Address,
  type Hex,
  decodeAbiParameters,
  zeroAddress,
} from "viem";
import { describe, expect, it } from "vitest";
import { EthProver } from "../../../lib/unruggable-gateways/src/eth/EthProver.ts";
import {
  GatewayProgram,
  GatewayRequest,
} from "../../../lib/unruggable-gateways/src/vm.ts";
import { expectVar } from "../../utils/expectVar.js";
import { labelToCanonicalId, splitName } from "../../utils/utils.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";

const connection = await hre.network.connect();

const EXIT_CODE_NO_RESOLVER = 2;
function createRegistryTraversalRequest({
  datastore,
  registry,
  namePrefix,
  timestamp,
}: {
  datastore: Address;
  registry: Address;
  namePrefix: string;
  timestamp: bigint;
}) {
  const SLOT_RD_ENTRIES = 0;
  const req = new GatewayRequest(2);
  for (const label of splitName(namePrefix)) {
    req.push(labelToCanonicalId(label));
  }
  req.push(registry).setOutput(0); // starting point
  req.setTarget(datastore);
  req.setSlot(SLOT_RD_ENTRIES);
  {
    const cmd = new GatewayProgram();
    cmd.pushOutput(0); // parent registry
    cmd.follow().follow(); // entry[registry][labelHash]
    cmd.read(); // read registryData (see: RegistryDatastore.sol)
    cmd.dup().push(0xffffffffffffffffn).and(); // extract expiry (first 64 bits)
    cmd.push(timestamp).gt().assertNonzero(1); // require expiry > timestamp
    cmd.shr(96); // extract subregistry (shift past expiry+tokenVersionId)
    cmd.offset(1).read().shr(32); // read slot 1, shift past eacVersionId to get resolver
    cmd.pushProgram(
      new GatewayProgram().requireNonzero(1).setOutput(1), // save resolver if set
    );
    cmd.evalLoop({ count: 1 }); // consume resolver, catch assert
    cmd.requireNonzero(1).setOutput(0); // require registry and save it
    req.pushProgram(cmd);
  }
  req.evalLoop({ failure: true, keep: true }); // outputs = [registry, resolver]
  req.pushOutput(1).requireNonzero(EXIT_CODE_NO_RESOLVER); // target resolver
  return req;
}

async function fixture() {
  const F = await deployV2Fixture(connection);
  return {
    ...F,
    getProver,
    traversalRequest,
  };
  async function getProver() {
    return EthProver.latest(new BrowserProvider(connection.provider));
  }
  function traversalRequest(
    name: string,
    timestamp = BigInt(Date.now()) / 1000n,
  ) {
    if (!name.endsWith(".eth")) throw new Error(`expected "eth": ${name}`);
    return createRegistryTraversalRequest({
      datastore: F.datastore.address,
      registry: F.ethRegistry.address,
      namePrefix: name.slice(0, -4),
      timestamp,
    });
  }
}

function decodeValues<T extends AbiParameter[]>(value: string, types: T) {
  return decodeAbiParameters(types, value as Hex);
}

function decodeValue<T extends AbiParameter["type"]>(value: string, type: T) {
  return decodeValues(value, [{ type }]);
}

describe("RegistryDatastore", () => {
  describe("Exact Traversal", () => {
    for (let depth = 1; depth <= 5; depth++) {
      it(`depth = ${depth}`, async () => {
        const F = await connection.networkHelpers.loadFixture(fixture);
        const name = "x.".repeat(depth) + "eth";
        const { dedicatedResolver, parentRegistry } = await F.setupName({
          name,
        });
        const prover = await F.getProver();
        const req = F.traversalRequest(name);
        //expect(req.encode(), "size").toHaveLength(116 + (1 + 32) * depth);
        const state = await prover.evalRequest(req);
        expect(state.needs, "proofs").toHaveLength(1 + 2 * depth);
        const values = await state.resolveOutputs();
        const [registry] = decodeValue(values[0], "address");
        const [resolver] = decodeValue(values[1], "address");
        expectVar({ registry }).toEqualAddress(parentRegistry.address);
        expectVar({ resolver }).toEqualAddress(dedicatedResolver.address);
      });
    }
  });

  describe("Wildcard Traversal", () => {
    for (let depth = 1; depth <= 3; depth++) {
      it(`depth = ${depth}`, async () => {
        const F = await connection.networkHelpers.loadFixture(fixture);
        const name = "test.eth";
        const { dedicatedResolver } = await F.setupName({ name });
        const wildName = "x.".repeat(depth) + name;
        const { parentRegistry } = await F.setupName({
          name: wildName,
          resolverAddress: zeroAddress,
        });
        const prover = await F.getProver();
        const req = F.traversalRequest(wildName);
        const state = await prover.evalRequest(req);
        const values = await state.resolveOutputs();
        const [registry] = decodeValue(values[0], "address");
        const [resolver] = decodeValue(values[1], "address");
        expectVar({ registry }).toEqualAddress(parentRegistry.address);
        expectVar({ resolver }).toEqualAddress(dedicatedResolver.address);
      });
    }
  });

  it("no resolver", async () => {
    const name = "test.eth";
    const F = await connection.networkHelpers.loadFixture(fixture);
    const prover = await F.getProver();
    const req = F.traversalRequest(name);
    const state = await prover.evalRequest(req);
    expect(state.exitCode).toEqual(EXIT_CODE_NO_RESOLVER);
  });

  it("expired", async () => {
    const name = "test.eth";
    const F = await connection.networkHelpers.loadFixture(fixture);
    const { timestamp } = await F.publicClient.getBlock();
    const expiry = timestamp + 10000n;
    const { dedicatedResolver } = await F.setupName({ name, expiry });
    const prover = await F.getProver();
    const state0 = await prover.evalRequest(F.traversalRequest(name));
    const values = await state0.resolveOutputs();
    const [resolver] = decodeValue(values[1], "address");
    expectVar({ resolver }).toEqualAddress(dedicatedResolver.address);
    const state1 = await prover.evalRequest(F.traversalRequest(name, expiry));
    expect(state1.exitCode).toEqual(EXIT_CODE_NO_RESOLVER);
  });
});
