/**
 * JavaScript wrapper for the VerifiableFactory contract
 * This file provides a utility class for deploying contracts using the VerifiableFactory
 */

export class VerifiableFactory {
  constructor(factoryContract, signer) {
    this.factory = factoryContract;
    this.signer = signer;
  }

  /**
   * Deploy a proxy contract using the VerifiableFactory
   * @param {string} implementation - The address of the implementation contract
   * @param {string} initData - The initialization data for the proxy
   * @param {string} salt - Optional salt for deterministic deployment
   * @returns {Promise<string>} - The address of the deployed proxy
   */
  async deploy(implementation, initData, salt = "") {
    const deploymentSalt = salt || ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes(`${implementation}-${Date.now()}`)
    );
    
    const tx = await this.factory.deployProxy(implementation, deploymentSalt, initData);
    const receipt = await tx.wait();
    
    const event = receipt.events.find(e => e.event === "ProxyDeployed");
    if (!event) {
      throw new Error("Failed to deploy proxy: ProxyDeployed event not found");
    }
    
    return event.args.proxyAddress;
  }

  /**
   * Verify a contract was deployed by this factory
   * @param {string} proxyAddress - The address of the proxy to verify
   * @returns {Promise<boolean>} - Whether the proxy was deployed by this factory
   */
  async verify(proxyAddress) {
    return await this.factory.verifyContract(proxyAddress);
  }
}
