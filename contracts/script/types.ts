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
  key: string;
  value: string;
}

export interface AddressChangedEventArgs {
  id: bigint;
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