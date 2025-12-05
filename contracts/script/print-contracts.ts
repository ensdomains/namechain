import { loadDeployments } from "rocketh";

const chainName = "sepoliaFresh";
const deployments = {
  v1: loadDeployments("deployments/l1/v1", chainName, false).deployments,
  l1: loadDeployments("deployments/l1", chainName, false).deployments,
  l2: loadDeployments("deployments/l2", chainName, false).deployments,
} as const;

function Contract(name: string, address: string) {
  this.name = name;
  this.address = address;
}

for (const chain of Object.keys(deployments)) {
  console.log(chain);
  const ctrcts = [];
  for (const contract of Object.keys(deployments[chain])) {
    ctrcts.push(new Contract(contract, deployments[chain][contract].address));
  }
  console.table(ctrcts, ["name", "address"]);
}
