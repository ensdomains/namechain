#!/usr/bin/env python3
"""
Test client for ENS MCP Server
"""

import asyncio
import json
import subprocess
import sys
from typing import Dict, Any

class ENSMCPClient:
    """Simple client for testing ENS MCP server"""
    
    def __init__(self, server_script: str = "ens_mcp_server.py"):
        self.server_script = server_script
        self.process = None
        self.message_id = 0
    
    async def start_server(self):
        """Start the MCP server process"""
        self.process = await asyncio.create_subprocess_exec(
            sys.executable, self.server_script,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        # Initialize the server
        await self.send_message({
            "jsonrpc": "2.0",
            "id": self.get_next_id(),
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "clientInfo": {
                    "name": "ENS Test Client",
                    "version": "1.0.0"
                }
            }
        })
    
    async def stop_server(self):
        """Stop the MCP server process"""
        if self.process:
            self.process.terminate()
            await self.process.wait()
    
    def get_next_id(self) -> int:
        """Get next message ID"""
        self.message_id += 1
        return self.message_id
    
    async def send_message(self, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send a message to the server and get response"""
        if not self.process or not self.process.stdin or not self.process.stdout:
            raise RuntimeError("Server not started or not properly initialized")
        
        # Send message
        message_str = json.dumps(message) + "\n"
        self.process.stdin.write(message_str.encode())
        await self.process.stdin.drain()
        
        # Read response
        response_line = await self.process.stdout.readline()
        response = json.loads(response_line.decode().strip())
        
        return response
    
    async def list_tools(self) -> Dict[str, Any]:
        """Get list of available tools"""
        return await self.send_message({
            "jsonrpc": "2.0",
            "id": self.get_next_id(),
            "method": "tools/list"
        })
    
    async def call_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call a tool"""
        return await self.send_message({
            "jsonrpc": "2.0",
            "id": self.get_next_id(),
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            }
        })
    
    async def resolve_ens_name(self, ens_name: str, coin_type: int = 60) -> Dict[str, Any]:
        """Resolve ENS name to address"""
        return await self.call_tool("resolve_ens_name", {
            "ens_name": ens_name,
            "coin_type": coin_type
        })
    
    async def reverse_resolve_address(self, address: str) -> Dict[str, Any]:
        """Reverse resolve address to ENS name"""
        return await self.call_tool("reverse_resolve_address", {
            "address": address
        })
    
    async def get_ens_text_record(self, ens_name: str, key: str) -> Dict[str, Any]:
        """Get ENS text record"""
        return await self.call_tool("get_ens_text_record", {
            "ens_name": ens_name,
            "key": key
        })
    
    async def get_ens_info(self, ens_name: str) -> Dict[str, Any]:
        """Get comprehensive ENS info"""
        return await self.call_tool("get_ens_info", {
            "ens_name": ens_name
        })


async def run_tests():
    """Run comprehensive tests"""
    print("🧪 Starting ENS MCP Server Tests")
    print("=" * 50)
    
    client = ENSMCPClient()
    
    try:
        # Start server
        print("🚀 Starting server...")
        await client.start_server()
        
        # List available tools
        print("\n📋 Available tools:")
        tools_response = await client.list_tools()
        if "result" in tools_response and "tools" in tools_response["result"]:
            for tool in tools_response["result"]["tools"]:
                print(f"  - {tool['name']}: {tool['description']}")
        
        # Test ENS resolution
        print("\n📍 Testing ENS Resolution:")
        test_names = ["vitalik.eth", "nick.eth", "brantly.eth"]
        
        for name in test_names:
            try:
                response = await client.resolve_ens_name(name)
                if "result" in response and "content" in response["result"]:
                    result = json.loads(response["result"]["content"][0]["text"])
                    if result["success"]:
                        print(f"  ✅ {name} -> {result['address']}")
                    else:
                        print(f"  ❌ {name} -> {result['error']}")
                else:
                    print(f"  ❌ {name} -> Error in response format")
            except Exception as e:
                print(f"  ❌ {name} -> Exception: {e}")
        
        # Test reverse resolution
        print("\n🔄 Testing Reverse Resolution:")
        test_address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"  # vitalik.eth
        try:
            response = await client.reverse_resolve_address(test_address)
            if "result" in response and "content" in response["result"]:
                result = json.loads(response["result"]["content"][0]["text"])
                if result["success"]:
                    print(f"  ✅ {test_address} -> {result['ens_name']}")
                else:
                    print(f"  ❌ {test_address} -> {result['error']}")
        except Exception as e:
            print(f"  ❌ {test_address} -> Exception: {e}")
        
        # Test text records
        print("\n📝 Testing Text Records:")
        text_tests = [
            ("vitalik.eth", "url"),
            ("vitalik.eth", "twitter"),
            ("nick.eth", "github")
        ]
        
        for name, key in text_tests:
            try:
                response = await client.get_ens_text_record(name, key)
                if "result" in response and "content" in response["result"]:
                    result = json.loads(response["result"]["content"][0]["text"])
                    if result["success"]:
                        value = result["value"] if result["value"] else "(empty)"
                        print(f"  ✅ {name} {key} -> {value}")
                    else:
                        print(f"  ❌ {name} {key} -> {result['error']}")
            except Exception as e:
                print(f"  ❌ {name} {key} -> Exception: {e}")
        
        # Test comprehensive info
        print("\n📊 Testing Comprehensive Info:")
        try:
            response = await client.get_ens_info("vitalik.eth")
            if "result" in response and "content" in response["result"]:
                result = json.loads(response["result"]["content"][0]["text"])
                if result["success"]:
                    print(f"  ✅ vitalik.eth info:")
                    print(f"      Address: {result.get('address', 'N/A')}")
                    print(f"      Owner: {result.get('owner', 'N/A')}")
                    print(f"      Resolver: {result.get('resolver', 'N/A')}")
                    
                    text_records = result.get("text_records", {})
                    if text_records:
                        print(f"      Text records: {len(text_records)} found")
                        for key, value in text_records.items():
                            print(f"        {key}: {value}")
                    else:
                        print("      Text records: None found")
                else:
                    print(f"  ❌ vitalik.eth info -> {result['error']}")
        except Exception as e:
            print(f"  ❌ vitalik.eth info -> Exception: {e}")
        
        # Test multi-chain resolution
        print("\n🌐 Testing Multi-chain Resolution:")
        multi_tests = [
            ("vitalik.eth", 60, "Ethereum"),
            ("vitalik.eth", 0, "Bitcoin"),
            ("vitalik.eth", 501, "Solana")
        ]
        
        for name, coin_type, chain in multi_tests:
            try:
                response = await client.resolve_ens_name(name, coin_type)
                if "result" in response and "content" in response["result"]:
                    result = json.loads(response["result"]["content"][0]["text"])
                    if result["success"]:
                        print(f"  ✅ {name} ({chain}) -> {result['address']}")
                    else:
                        print(f"  ❌ {name} ({chain}) -> {result['error']}")
            except Exception as e:
                print(f"  ❌ {name} ({chain}) -> Exception: {e}")
        
        print("\n✅ All tests completed!")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        # Stop server
        print("\n🛑 Stopping server...")
        await client.stop_server()


def main():
    """Main entry point"""
    print("ENS MCP Server Test Client")
    print("=" * 30)
    
    try:
        asyncio.run(run_tests())
    except KeyboardInterrupt:
        print("\n👋 Test interrupted by user")
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()