import { artifacts, execute } from "@rocketh";
import { labelToCanonicalId } from "../../test/utils/utils.ts";

export default execute(
  async ({ execute: write, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const ethTLDResolver =
      get<(typeof artifacts.ETHTLDResolver)["abi"]>("ETHTLDResolver");

    await write(rootRegistry, {
      account: deployer,
      functionName: "setResolver",
      args: [labelToCanonicalId("eth"), ethTLDResolver.address],
    });
  },
  {
    tags: ["SetETHTLDResolver", "l1"],
    dependencies: ["RootRegistry", "ETHTLDResolver"],
  },
);
