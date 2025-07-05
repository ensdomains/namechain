#!/usr/bin/env python3
"""
ENS MCP Server - A Model Context Protocol server for Ethereum Name Service resolution
"""

import asyncio
import json
import logging
from typing import Any, Dict, List, Optional, Union
from web3 import Web3
from web3.exceptions import NameNotFound
from ens import ENS
from ens.exceptions import ENSException
import argparse
import sys
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ENSMCPServer:
    """MCP Server for ENS resolution"""
    
    def __init__(self, rpc_url: str = "https://eth-mainnet.g.alchemy.com/v2/demo"):
        """Initialize the ENS MCP server
        
        Args:
            rpc_url: Ethereum RPC endpoint URL
        """
        self.rpc_url = rpc_url
        self.w3 = None
        self.ens = None
        self.initialize_web3()
    
    def initialize_web3(self):
        """Initialize Web3 and ENS instances"""
        try:
            self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
            if not self.w3.is_connected():
                logger.error(f"Failed to connect to Ethereum node at {self.rpc_url}")
                raise ConnectionError(f"Could not connect to Ethereum node")
            
            self.ens = ENS.from_web3(self.w3)
            logger.info(f"Successfully connected to Ethereum node at {self.rpc_url}")
            
        except Exception as e:
            logger.error(f"Failed to initialize Web3: {e}")
            raise
    
    def get_server_info(self) -> Dict[str, Any]:
        """Return server information"""
        return {
            "name": "ENS MCP Server",
            "version": "1.0.0",
            "description": "A Model Context Protocol server for Ethereum Name Service resolution",
            "author": "ENS MCP Team",
            "capabilities": {
                "tools": True,
                "resources": False,
                "prompts": False
            }
        }
    
    def get_available_tools(self) -> List[Dict[str, Any]]:
        """Return list of available tools"""
        return [
            {
                "name": "resolve_ens_name",
                "description": "Resolve an ENS name to an Ethereum address",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "ens_name": {
                            "type": "string",
                            "description": "The ENS name to resolve (e.g., 'vitalik.eth')"
                        },
                        "coin_type": {
                            "type": "integer",
                            "description": "Optional coin type for multi-chain address resolution (default: 60 for ETH)",
                            "default": 60
                        }
                    },
                    "required": ["ens_name"]
                }
            },
            {
                "name": "reverse_resolve_address",
                "description": "Reverse resolve an Ethereum address to find its primary ENS name",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "address": {
                            "type": "string",
                            "description": "The Ethereum address to reverse resolve (e.g., '0x...')"
                        }
                    },
                    "required": ["address"]
                }
            },
            {
                "name": "get_ens_text_record",
                "description": "Get a text record from an ENS name",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "ens_name": {
                            "type": "string",
                            "description": "The ENS name to query"
                        },
                        "key": {
                            "type": "string",
                            "description": "The text record key (e.g., 'url', 'email', 'twitter', 'github')"
                        }
                    },
                    "required": ["ens_name", "key"]
                }
            },
            {
                "name": "get_ens_info",
                "description": "Get comprehensive information about an ENS name",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "ens_name": {
                            "type": "string",
                            "description": "The ENS name to get information for"
                        }
                    },
                    "required": ["ens_name"]
                }
            }
        ]
    
    async def resolve_ens_name(self, ens_name: str, coin_type: int = 60) -> Dict[str, Any]:
        """Resolve ENS name to address"""
        try:
            if not self.ens:
                return {
                    "success": False,
                    "error": "ENS not initialized",
                    "ens_name": ens_name,
                    "coin_type": coin_type
                }
                
            # Clean up the ENS name
            ens_name = ens_name.strip().lower()
            
            if coin_type == 60:  # Ethereum
                address = self.ens.address(ens_name)
            else:  # Multi-chain
                address = self.ens.address(ens_name, coin_type=coin_type)
            
            if not address:
                return {
                    "success": False,
                    "error": f"No address found for ENS name: {ens_name}",
                    "ens_name": ens_name,
                    "coin_type": coin_type
                }
            
            return {
                "success": True,
                "ens_name": ens_name,
                "address": address,
                "coin_type": coin_type,
                "timestamp": datetime.utcnow().isoformat()
            }
            
        except ENSException as e:
            return {
                "success": False,
                "error": f"ENS error: {str(e)}",
                "ens_name": ens_name,
                "coin_type": coin_type
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Unexpected error: {str(e)}",
                "ens_name": ens_name,
                "coin_type": coin_type
            }
    
    async def reverse_resolve_address(self, address: str) -> Dict[str, Any]:
        """Reverse resolve address to ENS name"""
        try:
            if not self.w3 or not self.ens:
                return {
                    "success": False,
                    "error": "Web3 or ENS not initialized",
                    "address": address
                }
                
            # Clean up the address
            address = address.strip()
            
            # Validate address format
            if not self.w3.is_address(address):
                return {
                    "success": False,
                    "error": f"Invalid Ethereum address format: {address}",
                    "address": address
                }
            
            # Convert to checksum address
            checksum_address = self.w3.to_checksum_address(address)
            
            # Perform reverse resolution
            ens_name = self.ens.name(checksum_address)
            
            if not ens_name:
                return {
                    "success": False,
                    "error": f"No ENS name found for address: {checksum_address}",
                    "address": checksum_address
                }
            
            return {
                "success": True,
                "address": checksum_address,
                "ens_name": ens_name,
                "timestamp": datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Error during reverse resolution: {str(e)}",
                "address": address
            }
    
    async def get_ens_text_record(self, ens_name: str, key: str) -> Dict[str, Any]:
        """Get text record from ENS name"""
        try:
            if not self.ens:
                return {
                    "success": False,
                    "error": "ENS not initialized",
                    "ens_name": ens_name,
                    "key": key
                }
                
            # Clean up inputs
            ens_name = ens_name.strip().lower()
            key = key.strip().lower()
            
            # Get text record
            text_value = self.ens.get_text(ens_name, key)
            
            return {
                "success": True,
                "ens_name": ens_name,
                "key": key,
                "value": text_value,
                "timestamp": datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Error getting text record: {str(e)}",
                "ens_name": ens_name,
                "key": key
            }
    
    async def get_ens_info(self, ens_name: str) -> Dict[str, Any]:
        """Get comprehensive ENS information"""
        try:
            if not self.ens:
                return {
                    "success": False,
                    "error": "ENS not initialized",
                    "ens_name": ens_name
                }
                
            # Clean up the ENS name
            ens_name = ens_name.strip().lower()
            
            info = {
                "success": True,
                "ens_name": ens_name,
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Get basic resolution
            try:
                address = self.ens.address(ens_name)
                info["address"] = address
            except:
                info["address"] = None
            
            # Get owner
            try:
                owner = self.ens.owner(ens_name)
                info["owner"] = owner
            except:
                info["owner"] = None
            
            # Get resolver
            try:
                resolver = self.ens.resolver(ens_name)
                info["resolver"] = resolver.address if resolver and hasattr(resolver, 'address') else None
            except:
                info["resolver"] = None
            
            # Get common text records
            text_records = {}
            common_keys = ["url", "email", "twitter", "github", "discord", "telegram", "description"]
            
            for key in common_keys:
                try:
                    value = self.ens.get_text(ens_name, key)
                    if value:
                        text_records[key] = value
                except:
                    pass
            
            info["text_records"] = text_records
            
            return info
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Error getting ENS info: {str(e)}",
                "ens_name": ens_name
            }
    
    async def handle_tool_call(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Handle tool calls"""
        try:
            if tool_name == "resolve_ens_name":
                return await self.resolve_ens_name(
                    arguments["ens_name"],
                    arguments.get("coin_type", 60)
                )
            elif tool_name == "reverse_resolve_address":
                return await self.reverse_resolve_address(arguments["address"])
            elif tool_name == "get_ens_text_record":
                return await self.get_ens_text_record(
                    arguments["ens_name"],
                    arguments["key"]
                )
            elif tool_name == "get_ens_info":
                return await self.get_ens_info(arguments["ens_name"])
            else:
                return {
                    "success": False,
                    "error": f"Unknown tool: {tool_name}"
                }
        except Exception as e:
            return {
                "success": False,
                "error": f"Error handling tool call: {str(e)}"
            }
    
    async def handle_message(self, message: Dict[str, Any]) -> Dict[str, Any]:
        """Handle incoming MCP messages"""
        try:
            method = message.get("method")
            
            if method == "initialize":
                return {
                    "id": message.get("id"),
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {
                            "tools": {"listChanged": True}
                        },
                        "serverInfo": self.get_server_info()
                    }
                }
            
            elif method == "tools/list":
                return {
                    "id": message.get("id"),
                    "result": {
                        "tools": self.get_available_tools()
                    }
                }
            
            elif method == "tools/call":
                params = message.get("params", {})
                tool_name = params.get("name")
                arguments = params.get("arguments", {})
                
                result = await self.handle_tool_call(tool_name, arguments)
                
                return {
                    "id": message.get("id"),
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(result, indent=2)
                            }
                        ]
                    }
                }
            
            else:
                return {
                    "id": message.get("id"),
                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {method}"
                    }
                }
        
        except Exception as e:
            return {
                "id": message.get("id"),
                "error": {
                    "code": -32603,
                    "message": f"Internal error: {str(e)}"
                }
            }
    
    async def run_stdio(self):
        """Run the MCP server using stdio transport"""
        logger.info("Starting ENS MCP Server with stdio transport")
        
        try:
            while True:
                # Read message from stdin
                line = await asyncio.get_event_loop().run_in_executor(
                    None, sys.stdin.readline
                )
                
                if not line:
                    break
                
                try:
                    message = json.loads(line.strip())
                    response = await self.handle_message(message)
                    
                    # Write response to stdout
                    print(json.dumps(response), flush=True)
                    
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON received: {e}")
                    error_response = {
                        "error": {
                            "code": -32700,
                            "message": "Parse error"
                        }
                    }
                    print(json.dumps(error_response), flush=True)
                
        except KeyboardInterrupt:
            logger.info("Server shutdown requested")
        except Exception as e:
            logger.error(f"Server error: {e}")
        
        logger.info("ENS MCP Server stopped")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="ENS MCP Server")
    parser.add_argument(
        "--rpc-url",
        default="https://eth-mainnet.g.alchemy.com/v2/demo",
        help="Ethereum RPC endpoint URL"
    )
    parser.add_argument(
        "--transport",
        choices=["stdio", "test"],
        default="stdio",
        help="Transport method"
    )
    
    args = parser.parse_args()
    
    # Initialize server
    server = ENSMCPServer(rpc_url=args.rpc_url)
    
    if args.transport == "stdio":
        # Run with stdio transport
        asyncio.run(server.run_stdio())
    elif args.transport == "test":
        # Run test mode
        asyncio.run(test_server(server))


async def test_server(server: ENSMCPServer):
    """Test the server functionality"""
    print("🧪 Testing ENS MCP Server")
    print("=" * 50)
    
    # Test ENS resolution
    print("\n📍 Testing ENS Resolution:")
    result = await server.resolve_ens_name("vitalik.eth")
    print(f"vitalik.eth -> {json.dumps(result, indent=2)}")
    
    # Test reverse resolution
    print("\n🔄 Testing Reverse Resolution:")
    if result["success"] and result["address"]:
        reverse_result = await server.reverse_resolve_address(result["address"])
        print(f"{result['address']} -> {json.dumps(reverse_result, indent=2)}")
    
    # Test text record
    print("\n📝 Testing Text Records:")
    text_result = await server.get_ens_text_record("vitalik.eth", "url")
    print(f"vitalik.eth url -> {json.dumps(text_result, indent=2)}")
    
    # Test comprehensive info
    print("\n📊 Testing Comprehensive Info:")
    info_result = await server.get_ens_info("vitalik.eth")
    print(f"vitalik.eth info -> {json.dumps(info_result, indent=2)}")
    
    print("\n✅ Testing completed!")


if __name__ == "__main__":
    main()