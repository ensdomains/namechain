import { serveBatchGateway } from "../../lib/ens-contracts/test/fixtures/localBatchGateway.js";

// TODO: replace this with ["x-batch-gateway:true"] once viem updates

export async function launchBatchGateway() {
  const bg = await serveBatchGateway();
  after(bg.shutdown);
  return [bg.localBatchGatewayUrl];
}
