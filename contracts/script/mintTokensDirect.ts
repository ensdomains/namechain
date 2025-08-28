#!/usr/bin/env bun
import { createPublicClient, createWalletClient, http, parseEther, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const MOCK_USDC_ADDRESS = '0xe7f1725e7734ce288f8367e1bb143e90bb3f0512';
const MOCK_DAI_ADDRESS = '0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0';

const MOCK_ERC20_ABI = [
  {
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function'
  },
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function'
  }
];

async function main() {
  const targetWallet = process.argv[2];
  
  if (!targetWallet) {
    console.error('Usage: bun run script/mintTokensDirect.ts <WALLET_ADDRESS>');
    console.error('Example: bun run script/mintTokensDirect.ts 0x1234...');
    process.exit(1);
  }

  console.log(`Minting mock tokens to: ${targetWallet}`);
  console.log(`MockUSDC: ${MOCK_USDC_ADDRESS}`);
  console.log(`MockDAI: ${MOCK_DAI_ADDRESS}`);

  const l2Client = createPublicClient({
    chain: {
      id: 31338,
      name: 'L2 Local',
      nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
      rpcUrls: {
        default: { http: ['http://127.0.0.1:8546'] },
        public: { http: ['http://127.0.0.1:8546'] },
      },
    },
    transport: http('http://127.0.0.1:8546'),
  });

  const deployerAccount = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
  
  const walletClient = createWalletClient({
    account: deployerAccount,
    chain: {
      id: 31338,
      name: 'L2 Local',
      nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
      rpcUrls: {
        default: { http: ['http://127.0.0.1:8546'] },
        public: { http: ['http://127.0.0.1:8546'] },
      },
    },
    transport: http('http://127.0.0.1:8546'),
  });

  try {
    const usdcAmount = parseUnits('1000', 6);
    console.log(`Minting 1000 USDC...`);
    
    const usdcMintTx = await walletClient.writeContract({
      address: MOCK_USDC_ADDRESS,
      abi: MOCK_ERC20_ABI,
      functionName: 'mint',
      args: [targetWallet, usdcAmount],
    });

    console.log(`USDC minted! Transaction: ${usdcMintTx}`);

    const daiAmount = parseEther('1000');
    console.log(`Minting 1000 DAI...`);
    
    const daiMintTx = await walletClient.writeContract({
      address: MOCK_DAI_ADDRESS,
      abi: MOCK_ERC20_ABI,
      functionName: 'mint',
      args: [targetWallet, daiAmount],
    });

    console.log(`DAI minted! Transaction: ${daiMintTx}`);

    console.log('Waiting for transactions to be mined...');
    await new Promise(resolve => setTimeout(resolve, 2000));

    const usdcBalance = await l2Client.readContract({
      address: MOCK_USDC_ADDRESS,
      abi: MOCK_ERC20_ABI,
      functionName: 'balanceOf',
      args: [targetWallet],
    });

    const daiBalance = await l2Client.readContract({
      address: MOCK_DAI_ADDRESS,
      abi: MOCK_ERC20_ABI,
      functionName: 'balanceOf',
      args: [targetWallet],
    });

    console.log('\nToken minting complete!');
    console.log(`${targetWallet} now has:`);
    console.log(`   - USDC: ${Number(usdcBalance) / 1e6} USDC`);
    console.log(`   - DAI: ${Number(daiBalance) / 1e18} DAI`);
    console.log('\nYou can now use these tokens to register names from your frontend!');
    console.log(`   - Each name registration costs $10 (in either USDC or DAI)`);
    console.log(`   - Make sure to approve the ETHRegistrar contract to spend your tokens`);

  } catch (error) {
    console.error('Error minting tokens:', error);
    process.exit(1);
  }
}

main().catch(console.error);