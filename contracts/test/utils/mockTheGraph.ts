import type { ENSRegistration } from "../../script/preMigration.js";

export interface MockTheGraphOptions {
  registrations?: ENSRegistration[];
  errorMessage?: string;
  delay?: number;
}

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
