import type { ENSRegistration } from "../../script/preMigration.js";
import { getContract, keccak256, toHex, type Address } from "viem";
import BaseRegistrarArtifact from "../../artifacts/lib/ens-contracts/contracts/ethregistrar/BaseRegistrarImplementation.sol/BaseRegistrarImplementation.json" with { type: "json" };

const BASE_REGISTRAR_ABI = BaseRegistrarArtifact.abi;

function createMockTheGraphResponse(
  registrations: ENSRegistration[]
): Response {
  return new Response(
    JSON.stringify({
      data: {
        registrations,
      },
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
}

export interface DynamicTheGraphMock {
  registerName: (labelName: string, owner: Address, duration: bigint) => Promise<void>;
  fetch: (url: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
  getRegistrations: () => ENSRegistration[];
}

export function createDynamicTheGraphMock(
  l1Client: any,
  baseRegistrarAddress: Address
): DynamicTheGraphMock {
  const registeredNames = new Map<string, ENSRegistration>();

  // Capture original fetch before it gets mocked
  const originalFetch = globalThis.fetch;

  // Create fetch function once that dynamically accesses the map
  const fetchFn = async (url: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const urlString = url.toString();

    if (urlString.includes("thegraph.com")) {
      // Parse the request body to get pagination params
      if (init?.body) {
        const body = JSON.parse(init.body as string);
        const { first = 100, skip = 0 } = body.variables || {};

        // Return paginated results from current registrations
        const allRegs = Array.from(registeredNames.values());
        const paginatedResults = allRegs.slice(skip, skip + first);
        return createMockTheGraphResponse(paginatedResults);
      }

      // Default: return all registrations
      return createMockTheGraphResponse(Array.from(registeredNames.values()));
    }

    // Pass through all other requests (e.g., RPC calls) using original fetch
    return originalFetch(url, init);
  };

  return {
    async registerName(labelName: string, owner: Address, duration: bigint) {
      const tokenId = keccak256(toHex(labelName));

      // Check if caller is a controller
      const isController = await l1Client.readContract({
        address: baseRegistrarAddress,
        abi: BASE_REGISTRAR_ABI,
        functionName: "controllers",
        args: [l1Client.account.address],
      });

      // Add as controller if needed
      if (!isController) {
        await l1Client.writeContract({
          address: baseRegistrarAddress,
          abi: BASE_REGISTRAR_ABI,
          functionName: "addController",
          args: [l1Client.account.address],
        });
      }

      // Register the name
      await l1Client.writeContract({
        address: baseRegistrarAddress,
        abi: BASE_REGISTRAR_ABI,
        functionName: "register",
        args: [tokenId, owner, duration],
      });

      // Get expiry
      const expiry = await l1Client.readContract({
        address: baseRegistrarAddress,
        abi: BASE_REGISTRAR_ABI,
        functionName: "nameExpires",
        args: [tokenId],
      });

      const registrationDate = BigInt(Math.floor(Date.now() / 1000)) - duration;

      registeredNames.set(labelName, {
        id: tokenId,
        labelName,
        registrant: owner,
        expiryDate: expiry.toString(),
        registrationDate: registrationDate.toString(),
        domain: {
          name: `${labelName}.eth`,
          labelhash: tokenId,
          parent: {
            id: "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae", // .eth node
          },
        },
      });
    },

    fetch: fetchFn,

    getRegistrations() {
      return Array.from(registeredNames.values());
    },
  };
}
