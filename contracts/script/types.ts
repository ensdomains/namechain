export interface ResolverRecord {
  type: 'address' | 'text';
  value: string;
}

export interface LabelInfo {
  label: string;
  resolver: string | null;
  registry: string | null;
  chainId?: number;
  subregistry?: string;
}

export interface RegistryNode {
  chainId: number;
  expiry: number;
  labels: Map<string, LabelInfo>;
}

export interface ResolverUpdateEventArgs {
  id: bigint;
  resolver: string;
  record?: string;
}

export interface TextChangedEventArgs {
  node: `0x${string}`;
  name?: string;
  key: string;
  value: string;
}

export interface AddressChangedEventArgs {
  id: bigint;
  node: `0x${string}`;
  suffix?: string;
  coinType: bigint;
  newAddress: string;
  a?: string;
}

export interface SubregistryUpdateEventArgs {
  id: bigint;
  subregistry: string;
  expiry: bigint;
}

export interface NewSubnameEventArgs {
  labelHash: bigint;
  label: string;
}

export interface MetadataChangedEventArgs {
  name: string;
  value: string;
  chainId: number;
  l2RegistryAddress: string;
}

// Additional types from listNames.ts
export type LabelHash = string;
export type RegistryAddress = string;

export interface DecodedEvent {
  eventName: string;
  args: any;
}

export interface Log {
  data: string;
  topics: string[];
}

export interface Abi {
  // Define your ABI structure here if needed
} 