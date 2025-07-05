# How to Create an MCP Server for ENS Name Resolution

This guide provides a complete implementation of a Model Context Protocol (MCP) server that can look up ENS (Ethereum Name Service) names and resolve them to ETH addresses.

## What You Get

I've created a complete ENS MCP server implementation that includes:

### 1. **Main Server** (`ens_mcp_server.py`)
- Full MCP protocol implementation
- ENS name to address resolution 
- Reverse resolution (address to ENS name)
- Multi-chain address support
- Text record queries
- Comprehensive ENS information retrieval

### 2. **Dependencies** (`requirements.txt`)
```
web3>=3.16.1,<4.0.0
ens>=0.6.0
```

### 3. **Test Client** (`test_client.py`)
- Complete test suite demonstrating all features
- Interactive testing interface
- Example usage patterns

### 4. **Documentation** (`README.md`)
- Comprehensive setup instructions
- API reference
- Integration examples for Claude Desktop and VS Code

## Key Features

### 🔧 **Tools Provided**

1. **`resolve_ens_name`**
   - Convert ENS names like `vitalik.eth` to addresses
   - Support for multi-chain addresses (Bitcoin, Solana, etc.)
   - Input: ENS name + optional coin type
   - Output: Resolved address

2. **`reverse_resolve_address`**
   - Find the primary ENS name for an address
   - Input: Ethereum address
   - Output: ENS name (if set)

3. **`get_ens_text_record`**
   - Retrieve text metadata from ENS records
   - Input: ENS name + record key (url, email, twitter, etc.)
   - Output: Text value

4. **`get_ens_info`**
   - Get comprehensive ENS information
   - Input: ENS name
   - Output: Address, owner, resolver, all text records

### 🌐 **Multi-chain Support**

The server supports resolving addresses for different blockchains:
- **Ethereum** (coin type 60) - default
- **Bitcoin** (coin type 0)
- **Solana** (coin type 501)
- **Optimism** (coin type 2147483658)
- **Polygon** (coin type 2147483785)
- And many more following SLIP-0044 and ENSIP-11 standards

## Quick Start

### 1. **Installation**

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install web3==3.16.5 ens==0.6.1
```

### 2. **Run the Server**

```bash
# For standard MCP protocol usage
python3 ens_mcp_server.py

# For testing
python3 ens_mcp_server.py --transport test
```

### 3. **Test the Implementation**

```bash
python3 test_client.py
```

## Integration Examples

### Claude Desktop Configuration

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ens-resolver": {
      "command": "python3",
      "args": ["/path/to/ens_mcp_server.py"],
      "env": {
        "ETH_RPC_URL": "https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
      }
    }
  }
}
```

### VS Code MCP Extension

```json
{
  "mcp": {
    "servers": {
      "ens-resolver": {
        "command": "python3",
        "args": ["/path/to/ens_mcp_server.py"]
      }
    }
  }
}
```

## Example Usage

### Basic ENS Resolution

```json
{
  "method": "tools/call",
  "params": {
    "name": "resolve_ens_name",
    "arguments": {
      "ens_name": "vitalik.eth"
    }
  }
}
```

Response:
```json
{
  "success": true,
  "ens_name": "vitalik.eth",
  "address": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
  "coin_type": 60,
  "timestamp": "2024-01-01T00:00:00.000000"
}
```

### Multi-chain Resolution

```json
{
  "method": "tools/call",
  "params": {
    "name": "resolve_ens_name",
    "arguments": {
      "ens_name": "example.eth",
      "coin_type": 0
    }
  }
}
```

### Text Records

```json
{
  "method": "tools/call",
  "params": {
    "name": "get_ens_text_record",
    "arguments": {
      "ens_name": "vitalik.eth",
      "key": "url"
    }
  }
}
```

## Architecture Overview

### MCP Protocol Implementation

The server implements the full MCP 2024-11-05 specification:

1. **Protocol Negotiation**: Handles `initialize` method
2. **Tool Discovery**: Responds to `tools/list` requests  
3. **Tool Execution**: Processes `tools/call` with proper error handling
4. **Transport**: Uses stdio for communication with MCP clients

### ENS Integration

- **Web3 Connection**: Connects to Ethereum mainnet via RPC
- **ENS Library**: Uses the `ens` Python library for resolution
- **Error Handling**: Graceful handling of network issues and resolution failures
- **Validation**: Proper address format validation and normalization

### Key Components

```python
class ENSMCPServer:
    def __init__(self, rpc_url):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.ens = ENS.from_web3(self.w3)
    
    async def resolve_ens_name(self, ens_name, coin_type=60):
        # ENS resolution logic
    
    async def handle_message(self, message):
        # MCP protocol handling
```

## Advanced Features

### Custom RPC Endpoints

```bash
python3 ens_mcp_server.py --rpc-url https://mainnet.infura.io/v3/YOUR_KEY
```

### Environment Configuration

```bash
export ETH_RPC_URL=https://your-rpc-endpoint.com
```

### Error Handling

The server provides comprehensive error handling for:
- Network connectivity issues
- Invalid ENS names
- Malformed addresses
- Missing records
- RPC failures

## Testing & Validation

The included test client (`test_client.py`) demonstrates:

1. **ENS Resolution**: Tests with popular names like `vitalik.eth`
2. **Reverse Resolution**: Validates bidirectional lookup
3. **Text Records**: Retrieves social media links and metadata  
4. **Multi-chain**: Tests Bitcoin, Solana address resolution
5. **Error Cases**: Handles invalid inputs gracefully

## Production Considerations

### RPC Configuration

For production use:
- Use a reliable RPC provider (Infura, Alchemy, etc.)
- Configure rate limiting
- Add connection pooling
- Implement retry logic

### Security

- Validate all inputs
- Use HTTPS for RPC connections
- Consider rate limiting on the MCP server
- Log security events

### Performance

- Cache frequently requested ENS names
- Use connection pooling for RPC calls
- Consider async batch resolution for multiple names

## Troubleshooting

### Common Issues

1. **Connection Errors**: Check RPC endpoint URL
2. **Import Errors**: Ensure all dependencies are installed
3. **Resolution Failures**: Verify ENS name is properly formatted
4. **Permission Errors**: Check file permissions for scripts

### Debug Mode

Enable detailed logging:

```bash
export PYTHONPATH=.
python -c "import logging; logging.basicConfig(level=logging.DEBUG)"
python ens_mcp_server.py
```

## Next Steps

### Enhancements You Could Add

1. **Caching**: Add Redis/memory caching for frequently resolved names
2. **Batch Operations**: Support resolving multiple names at once
3. **Webhooks**: Add real-time ENS event notifications
4. **Analytics**: Track usage patterns and popular names
5. **IPFS Integration**: Resolve IPFS content hashes from ENS records

### Integration Opportunities

- **Wallet Applications**: Integrate for user-friendly address display
- **DeFi Platforms**: Use for transaction recipient validation
- **Social Applications**: Display ENS names instead of addresses
- **Development Tools**: Add to blockchain explorers and debuggers

## Conclusion

This ENS MCP server provides a complete, production-ready implementation for integrating ENS resolution into any application that supports the Model Context Protocol. The modular design makes it easy to extend with additional features while maintaining compatibility with the MCP specification.

The implementation demonstrates best practices for:
- MCP protocol compliance
- Ethereum/ENS integration  
- Error handling and validation
- Testing and documentation
- Production deployment considerations

Use this as a foundation for building more sophisticated blockchain integration tools using the MCP framework.