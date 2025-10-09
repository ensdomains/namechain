import type { ENSRegistration } from "../../script/preMigration.js";
import { getContract, keccak256, toHex, type Address } from "viem";
import BaseRegistrarArtifact from "../../artifacts/lib/ens-contracts/contracts/ethregistrar/BaseRegistrarImplementation.sol/BaseRegistrarImplementation.json" with { type: "json" };

const BASE_REGISTRAR_ABI = BaseRegistrarArtifact.abi;

export async function setupBaseRegistrarController(
  l1Client: any,
  baseRegistrarAddress: Address,
  ownerAddress: Address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
): Promise<void> {
  await l1Client.impersonateAccount({ address: ownerAddress });
  await l1Client.writeContract({
    account: ownerAddress,
    address: baseRegistrarAddress,
    abi: BASE_REGISTRAR_ABI,
    functionName: "addController",
    args: [l1Client.account.address],
  });
  await l1Client.stopImpersonatingAccount({ address: ownerAddress });
}

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

export interface TheGraphMock {
  registerName: (labelName: string, owner: Address, duration: bigint) => Promise<void>;
  fetch: (url: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
  getRegistrations: () => ENSRegistration[];
}

export function createTheGraphMock(
  l1Client: any,
  baseRegistrarAddress: Address
): TheGraphMock {
  const registeredNames = new Map<string, ENSRegistration>();

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

    // Pass through all other requests
    return fetch(url, init);
  };

  return {
    async registerName(labelName: string, owner: Address, duration: bigint) {
      const tokenId = keccak256(toHex(labelName));

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
