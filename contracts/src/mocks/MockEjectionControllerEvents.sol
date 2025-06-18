// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

event NameEjectedToL1(bytes dnsEncodedName, address owner, address subregistry, uint64 expires);
event NameEjectedToL2(bytes dnsEncodedName, address l2Owner, address l2Subregistry);
