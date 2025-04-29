export function ensArtifact(name: string) {
  return new URL(`./ens-contracts/${name}.json`, import.meta.url);
}

export function urgArtifact(name: string) {
  return new URL(
    `../../lib/unruggable-gateways/artifacts/${name}.sol/${name}.json`,
    import.meta.url,
  );
}
