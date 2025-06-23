export type StorageLayout = {
  storage: {
    astId: number;
    contract: string;
    label: string;
    offset: number;
    slot: string;
    type: string;
  }[];
  types: Record<
    string,
    {
      encoding: string;
      label: string;
      numberOfBytes: string;
    } & (
      | {
          key: string;
          value: string;
        }
      | {}
    )
  >;
};
