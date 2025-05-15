// SPDX-License-Identifier: MIT

/**
 * Encodes a domain name into DNS format
 * @param {string} name The domain name to encode
 * @returns {Uint8Array} The DNS-encoded name
 */
export function dnsEncodeName(name) {
  if (!name) {
    return new Uint8Array(1);
  }
  
  const parts = name.split('.');
  let result = new Uint8Array(name.length + 2); // +2 for length bytes and null terminator
  let offset = 0;
  
  for (const part of parts) {
    result[offset] = part.length;
    offset++;
    
    for (let i = 0; i < part.length; i++) {
      result[offset] = part.charCodeAt(i);
      offset++;
    }
  }
  
  result[offset] = 0; // null terminator
  
  return result;
}

/**
 * Calculates the namehash of a domain name
 * @param {string} name The domain name to hash
 * @returns {string} The namehash
 */
export function namehash(name) {
  let node = '0x0000000000000000000000000000000000000000000000000000000000000000';
  
  if (!name) {
    return node;
  }
  
  const labels = name.split('.');
  
  for (let i = labels.length - 1; i >= 0; i--) {
    const label = labels[i];
    const labelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(label));
    node = ethers.utils.keccak256(ethers.utils.concat([node, labelHash]));
  }
  
  return node;
}
