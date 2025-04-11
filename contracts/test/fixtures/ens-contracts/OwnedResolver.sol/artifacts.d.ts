// This file was autogenerated by hardhat-viem, do not edit it.
// prettier-ignore
// tslint:disable
// eslint-disable

import "hardhat/types/artifacts";
import type { GetContractReturnType } from "@nomicfoundation/hardhat-viem/types";

import { OwnedResolver$Type } from "./OwnedResolver.js";

declare module "hardhat/types/artifacts" {
  interface ArtifactsMap {
    ["OwnedResolver"]: OwnedResolver$Type;
    ["contracts/resolvers/OwnedResolver.sol:OwnedResolver"]: OwnedResolver$Type;
  }

  interface ContractTypesMap {
    ["OwnedResolver"]: GetContractReturnType<OwnedResolver$Type["abi"]>;
    ["contracts/resolvers/OwnedResolver.sol:OwnedResolver"]: GetContractReturnType<OwnedResolver$Type["abi"]>;
  }
}
