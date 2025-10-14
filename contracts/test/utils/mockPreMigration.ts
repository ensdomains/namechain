import type { ENSRegistration } from "../../script/preMigration.js";
import { keccak256, toHex, type Address } from "viem";
import { writeFileSync } from "node:fs";
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

export interface CSVTestHelper {
  registerName: (labelName: string, owner: Address, duration: bigint) => Promise<void>;
  writeCSV: (filePath: string) => void;
  getRegistrations: () => ENSRegistration[];
}

export function createCSVTestHelper(
  l1Client: any,
  baseRegistrarAddress: Address
): CSVTestHelper {
  const registeredNames = new Map<string, { labelName: string; owner: Address; expiry: bigint }>();

  return {
    async registerName(labelName: string, owner: Address, duration: bigint) {
      const tokenId = keccak256(toHex(labelName));

      await l1Client.writeContract({
        address: baseRegistrarAddress,
        abi: BASE_REGISTRAR_ABI,
        functionName: "register",
        args: [tokenId, owner, duration],
      });

      const expiry = await l1Client.readContract({
        address: baseRegistrarAddress,
        abi: BASE_REGISTRAR_ABI,
        functionName: "nameExpires",
        args: [tokenId],
      });

      registeredNames.set(labelName, {
        labelName,
        owner,
        expiry,
      });
    },

    writeCSV(filePath: string) {
      const csvLines = [
        'node,name,labelHash,owner,parentName,parentLabelHash,labelName,registrationDate,expiryDate'
      ];

      for (const { labelName, owner, expiry } of registeredNames.values()) {
        const tokenId = keccak256(toHex(labelName));
        const registrationDate = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');
        const expiryDate = new Date(Number(expiry) * 1000).toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');

        csvLines.push(
          `${tokenId},${labelName}.eth,${tokenId},${owner},eth,0x4f5b812789fc606be1b3b16908db13fc7a9adf7ca72641f84d75b47069d3d7f0,${labelName},${registrationDate},${expiryDate}`
        );
      }

      writeFileSync(filePath, csvLines.join('\n'), 'utf-8');
    },

    getRegistrations() {
      return Array.from(registeredNames.values()).map(({ labelName }) => ({ labelName }));
    },
  };
}
