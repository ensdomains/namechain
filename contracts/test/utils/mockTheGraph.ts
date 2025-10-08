import type { ENSRegistration } from "../../script/preMigration.js";
import { getContract, keccak256, toHex, type Address } from "viem";

export interface MockTheGraphOptions {
  registrations?: ENSRegistration[];
  errorMessage?: string;
  delay?: number;
}

export interface MockMainnetOptions {
  nameExpiries?: Map<string, bigint>;
  defaultExpiry?: bigint;
}

const BASE_REGISTRAR_ABI = [
  {
    inputs: [{ internalType: "uint256", name: "id", type: "uint256" }],
    name: "nameExpires",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "uint256", name: "id", type: "uint256" },
      { internalType: "address", name: "owner", type: "address" },
      { internalType: "uint256", name: "duration", type: "uint256" },
    ],
    name: "register",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "controller", type: "address" }],
    name: "addController",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "", type: "address" }],
    name: "controllers",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export function createMockTheGraphResponse(
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

export function createMockTheGraphError(message: string): Response {
  return new Response(
    JSON.stringify({
      errors: [{ message }],
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
}

export function createMockRegistrations(count: number, prefix = "test"): ENSRegistration[] {
  const baseExpiry = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now

  return Array.from({ length: count }, (_, i) => ({
    id: `0x${i.toString(16).padStart(64, "0")}`,
    labelName: `${prefix}${i + 1}`,
    registrant: `0x${"1234567890abcdef".repeat(5)}`,
    expiryDate: (baseExpiry + i * 86400).toString(), // Stagger expiry dates
    registrationDate: (baseExpiry - 31536000 + i * 86400).toString(),
    domain: {
      name: `${prefix}${i + 1}.eth`,
      labelhash: `0x${(i + 1).toString(16).padStart(64, "0")}`,
      parent: {
        id: "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae", // .eth node
      },
    },
  }));
}

export function mockTheGraphFetch(
  options: MockTheGraphOptions = {}
): (url: RequestInfo | URL, init?: RequestInit) => Promise<Response> {
  const { registrations = [], errorMessage, delay = 0 } = options;

  return async (url: RequestInfo | URL, init?: RequestInit) => {
    const urlString = url.toString();

    if (urlString.includes("thegraph.com")) {
      // Add delay if specified
      if (delay > 0) {
        await new Promise((resolve) => setTimeout(resolve, delay));
      }

      // Return error if specified
      if (errorMessage) {
        return createMockTheGraphError(errorMessage);
      }

      // Parse the request body to get pagination params
      if (init?.body) {
        const body = JSON.parse(init.body as string);
        const { first = 100, skip = 0 } = body.variables || {};

        // Return paginated results
        const paginatedResults = registrations.slice(skip, skip + first);
        return createMockTheGraphResponse(paginatedResults);
      }

      // Default: return all registrations
      return createMockTheGraphResponse(registrations);
    }

    // Pass through all other requests (e.g., RPC calls)
    return fetch(url, init);
  };
}

export function createMockMainnetClient(options: MockMainnetOptions = {}) {
  const { nameExpiries = new Map(), defaultExpiry = BigInt(Math.floor(Date.now() / 1000) + 31536000) } = options;

  return {
    readContract: async ({ functionName, args }: { functionName: string; args: any[] }) => {
      if (functionName === "nameExpires") {
        const tokenId = args[0] as string;
        return nameExpiries.get(tokenId) ?? defaultExpiry;
      }
      throw new Error(`Unexpected function call: ${functionName}`);
    },
  };
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
