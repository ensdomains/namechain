# Scripts Documentation

Quick reference for the available scripts in this project.

## 📋 List Registered Names

**Script:** `listRegisteredNames.ts`  
**Command:** `bun run list-names`  
**Purpose:** Lists all registered domain names in a table format  
**Shows:** Name, Owner, Duration, Total Cost (USD)  
**Use case:** Check which names are registered and who owns them

## 🪙 Mint Mock Tokens

**Script:** `mintTokensDirect.ts`  
**Command:** `bun run mint-tokens <WALLET_ADDRESS>`  
**Purpose:** Mints 1000 MockUSDC and 1000 MockDAI to a specified address  
**Use case:** Give test tokens to addresses for testing name registration

## 👀 Watch Name Registrations

**Script:** `watchNameRegistrations.ts`  
**Command:** `bun run watch-names`  
**Purpose:** Real-time monitoring of new name registrations  
**Shows:** New registrations as they happen with owner and cost details  
**Use case:** Monitor registration activity during development/testing

## 🌐 CORS Proxy

**Script:** `corsProxy.ts`  
**Command:** `bun run cors-proxy`  
**Purpose:** Adds CORS headers to Alto bundler responses for frontend access  
**Port:** 4339 (proxies to Alto L2 on 4338)  
**Use case:** Enable frontend to communicate with AA infrastructure

## 🚀 Development Environment

**Script:** `runDevnet.ts`  
**Command:** `bun run devnet`  
**Purpose:** Sets up the complete development environment with AA Kit  
**Shows:** Contract addresses, endpoints, test accounts  
**Use case:** Initialize the local development setup

## 📝 Usage Examples

```bash
# List all registered names
bun run list-names

# Mint tokens to an address
bun run mint-tokens 0x1234...

# Watch for new registrations
bun run watch-names

# Start CORS proxy
bun run cors-proxy

# Setup devnet
bun run devnet
```

## 🔧 Prerequisites

- Running local blockchain (Anvil/Hardhat)
- AA Kit infrastructure (Alto bundlers, mock paymasters)
- Contracts deployed
- Bun package manager
