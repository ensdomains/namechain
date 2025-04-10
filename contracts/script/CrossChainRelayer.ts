/**
 * Class for handling cross-chain message relaying between L1 and L2
 */
export class CrossChainRelayer {
  l1Bridge: any;
  l2Bridge: any;
  L1: any; // Foundry instance for L1
  L2: any; // Foundry instance for L2
  
  /**
   * Create a new CrossChainRelayer
   * @param l1Bridge L1 bridge contract
   * @param l2Bridge L2 bridge contract
   * @param L1 L1 Foundry instance
   * @param L2 L2 Foundry instance
   */
  constructor(l1Bridge, l2Bridge, L1, L2) {
    this.l1Bridge = l1Bridge;
    this.l2Bridge = l2Bridge;
    this.L1 = L1;
    this.L2 = L2;
    
    this.setupListeners();
  }
  
  /**
   * Set up event listeners for cross-chain message passing
   */
  setupListeners() {
    console.log("Setting up cross-chain event listeners...");
    
    // Listen for L1->L2 messages
    this.l1Bridge.on("L1ToL2Message", async (message, event) => {
      console.log(`Relaying message from L1 to L2:`);
      console.log(`Message: ${message}`);
      console.log(`Transaction: ${event.log.transactionHash}`);
      
      try {
        // Create a transaction to relay the message to L2
        const tx = await this.L2.confirm(this.l2Bridge.receiveMessageFromL1(message));
        console.log(`Message relayed to L2, tx hash: ${tx.hash}`);
      } catch (error) {
        console.error(`Error relaying message to L2:`, error);
      }
    });
    
    // Listen for L2->L1 messages
    this.l2Bridge.on("L2ToL1Message", async (message, event) => {
      console.log(`Relaying message from L2 to L1:`);
      console.log(`Message: ${message}`);
      console.log(`Transaction: ${event.log.transactionHash}`);
      
      try {
        // Create a transaction to relay the message to L1
        const tx = await this.L1.confirm(this.l1Bridge.receiveMessageFromL2(message));
        console.log(`Message relayed to L1, tx hash: ${tx.hash}`);
      } catch (error) {
        console.error(`Error relaying message to L1:`, error);
      }
    });
    
    console.log("Cross-chain event listeners set up successfully");
  }
  
  /**
   * Manually relay a message between chains
   * @param fromL1ToL2 true if relaying from L1 to L2, false for L2 to L1
   * @param message Message to relay
   * @returns Transaction hash
   */
  async manualRelay(fromL1ToL2, message) {
    try {
      if (fromL1ToL2) {
        console.log(`Manually relaying message from L1 to L2`);
        const tx = await this.L2.confirm(this.l2Bridge.receiveMessageFromL1(message));
        console.log(`Message relayed to L2, tx hash: ${tx.hash}`);
        return tx.hash;
      } else {
        console.log(`Manually relaying message from L2 to L1`);
        const tx = await this.L1.confirm(this.l1Bridge.receiveMessageFromL2(message));
        console.log(`Message relayed to L1, tx hash: ${tx.hash}`);
        return tx.hash;
      }
    } catch (error) {
      console.error(`Error in manual relay:`, error);
      throw error;
    }
  }
}
