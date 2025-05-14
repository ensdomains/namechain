/**
 * JavaScript wrapper for the VerifiableFactory contract
 * This file provides a utility class for deploying contracts using the VerifiableFactory
 */
import { keccak256, stringToBytes } from "viem";

export class VerifiableFactory {
  constructor(factoryContract, walletClient) {
    this.factory = factoryContract;
    this.walletClient = walletClient;
  }

  /**
   * Deploy a proxy contract using the VerifiableFactory
   * @param {string} implementation - The address of the implementation contract
   * @param {string} initData - The initialization data for the proxy
   * @param {string} salt - Optional salt for deterministic deployment
   * @returns {Promise<string>} - The address of the deployed proxy
   */
  async deploy(implementation, initData, salt = "") {
    const deploymentSalt = salt || keccak256(
      stringToBytes(`${implementation}-${Date.now()}`)
    );
    
    const hash = await this.factory.write.deployProxy(
      [implementation, deploymentSalt, initData],
      { account: this.walletClient.account }
    );
    
    // Wait for transaction receipt
    const publicClient = await hre.viem.getPublicClient();
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    
    // Find the ProxyDeployed event
    const proxyDeployedEvents = receipt.logs
      .filter(log => {
        try {
          const event = this.factory.abi.find(item => 
            item.type === 'event' && item.name === 'ProxyDeployed'
          );
          if (!event) return false;
          
          // Check if the log's topics[0] matches the event signature
          const eventSignature = keccak256(
            stringToBytes(`${event.name}(${event.inputs.map(i => i.type).join(',')})`)
          );
          return log.topics[0] === eventSignature;
        } catch (e) {
          return false;
        }
      });
    
    if (proxyDeployedEvents.length === 0) {
      throw new Error("Failed to deploy proxy: ProxyDeployed event not found");
    }
    
    // For simplicity in this implementation, just return the address from the logs
    // In a production environment, you would want to properly decode the event
    const publicClient = await hre.viem.getPublicClient();
    
    // Get the deployment transaction receipt
    const deploymentReceipt = await publicClient.waitForTransactionReceipt({ 
      hash: hash,
      confirmations: 1
    });
    
    // Get contract creation events
    const contractAddress = deploymentReceipt.logs[0].address;
    
    return contractAddress;
  }

  /**
   * Verify a contract was deployed by this factory
   * @param {string} proxyAddress - The address of the proxy to verify
   * @returns {Promise<boolean>} - Whether the proxy was deployed by this factory
   */
  async verify(proxyAddress) {
    return await this.factory.read.verifyContract([proxyAddress]);
  }
}
