# ENS MCP Server

A Model Context Protocol (MCP) server for Ethereum Name Service (ENS) resolution. This server provides tools to resolve ENS names to addresses, perform reverse lookups, and query ENS records.

## Features

- **ENS Name Resolution**: Convert ENS names (like `vitalik.eth`) to Ethereum addresses
- **Reverse Resolution**: Find the primary ENS name for an Ethereum address
- **Multi-chain Support**: Resolve addresses for different blockchains using coin types
- **Text Record Queries**: Get text records like URLs, emails, social media handles
- **Comprehensive ENS Info**: Get all available information about an ENS name

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Run the server:
```bash
python ens_mcp_server.py
```

3. For testing:
```bash
python ens_mcp_server.py --transport test
```

## Usage

### Basic ENS Resolution

The server provides several tools accessible through the MCP protocol:

#### 1. Resolve ENS Name to Address

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

#### 2. Reverse Resolve Address to ENS Name

```json
{
  "method": "tools/call",
  "params": {
    "name": "reverse_resolve_address",
    "arguments": {
      "address": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    }
  }
}
```

#### 3. Get Text Records

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

#### 4. Get Comprehensive ENS Information

```json
{
  "method": "tools/call",
  "params": {
    "name": "get_ens_info",
    "arguments": {
      "ens_name": "vitalik.eth"
    }
  }
}
```

### Multi-chain Address Resolution

The server supports resolving addresses for different blockchains using coin types:

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

**Common Coin Types:**
- `0` - Bitcoin
- `2` - Litecoin
- `60` - Ethereum (default)
- `501` - Solana
- `2147483658` - Optimism
- `2147483785` - Polygon

## Configuration

### RPC Endpoint

By default, the server uses a demo Ethereum RPC endpoint. For production use, configure your own RPC endpoint:

```bash
python ens_mcp_server.py --rpc-url https://mainnet.infura.io/v3/YOUR_PROJECT_ID
```

### Environment Variables

You can also use environment variables:

```bash
export ETH_RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
```

## Integration with MCP Clients

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ens-resolver": {
      "command": "python",
      "args": ["/path/to/ens_mcp_server.py"],
      "env": {
        "ETH_RPC_URL": "https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
      }
    }
  }
}
```

### VS Code MCP Extension

Add to your MCP configuration:

```json
{
  "mcp": {
    "servers": {
      "ens-resolver": {
        "command": "python",
        "args": ["/path/to/ens_mcp_server.py"],
        "env": {
          "ETH_RPC_URL": "https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
        }
      }
    }
  }
}
```

## API Reference

### Available Tools

#### `resolve_ens_name`
- **Description**: Resolve an ENS name to an Ethereum address
- **Parameters**:
  - `ens_name` (string, required): The ENS name to resolve
  - `coin_type` (integer, optional): Coin type for multi-chain resolution (default: 60)
- **Returns**: Address resolution result

#### `reverse_resolve_address`
- **Description**: Reverse resolve an Ethereum address to find its primary ENS name
- **Parameters**:
  - `address` (string, required): The Ethereum address to reverse resolve
- **Returns**: ENS name resolution result

#### `get_ens_text_record`
- **Description**: Get a text record from an ENS name
- **Parameters**:
  - `ens_name` (string, required): The ENS name to query
  - `key` (string, required): The text record key
- **Returns**: Text record value

#### `get_ens_info`
- **Description**: Get comprehensive information about an ENS name
- **Parameters**:
  - `ens_name` (string, required): The ENS name to get information for
- **Returns**: Complete ENS information including address, owner, resolver, and text records

### Response Format

All tools return JSON responses with the following structure:

```json
{
  "success": true|false,
  "error": "error message (if success is false)",
  "timestamp": "ISO timestamp",
  "...": "additional fields specific to each tool"
}
```

## Error Handling

The server handles various error conditions:

- **Invalid ENS names**: Returns appropriate error messages
- **Network connectivity issues**: Graceful degradation
- **ENS resolution failures**: Clear error reporting
- **Invalid addresses**: Address format validation

## Development

### Running Tests

```bash
python ens_mcp_server.py --transport test
```

### Adding New Features

1. Add new tool definitions to `get_available_tools()`
2. Implement the tool logic as an async method
3. Add the tool to the `handle_tool_call()` method
4. Update documentation

### Debugging

Enable debug logging:

```bash
export PYTHONPATH=.
python -c "import logging; logging.basicConfig(level=logging.DEBUG)"
python ens_mcp_server.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the GitHub repository
- Check the ENS documentation at https://docs.ens.domains/
- Review the MCP specification at https://modelcontextprotocol.io/

## Examples

### Resolving Popular ENS Names

```python
# Test with popular ENS names
test_names = [
    "vitalik.eth",
    "nick.eth", 
    "brantly.eth",
    "jefflau.eth"
]

for name in test_names:
    result = await server.resolve_ens_name(name)
    print(f"{name} -> {result['address'] if result['success'] else 'Not found'}")
```

### Batch Resolution

```python
# Resolve multiple names efficiently
async def batch_resolve(names):
    tasks = [server.resolve_ens_name(name) for name in names]
    results = await asyncio.gather(*tasks)
    return dict(zip(names, results))
```

### Getting Social Media Links

```python
# Get social media information
social_keys = ["twitter", "github", "discord", "telegram"]
for key in social_keys:
    result = await server.get_ens_text_record("vitalik.eth", key)
    if result["success"] and result["value"]:
        print(f"{key}: {result['value']}")
```
