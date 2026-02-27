# MCP Test App

Test app for the `butschster/mcp-server` module. Demonstrates two separate MCP HTTP endpoints with scope filtering —
a public endpoint and an admin endpoint, each exposing different sets of tools.

## Endpoints

| Endpoint | Scope | Auth | Tools visible |
|---|---|---|
| `/api/mcp` | *(none)* | None | `echo`, `add`, `greet` |
| `/api/admin/mcp` | `admin` | `Authorization: Bearer secret-admin-token` | `echo`, `add`, `greet` + `server_info`, `reset` |

Public tools (no `mcp.scope`) are visible on both endpoints.
Admin tools (`mcp.scope: "admin"`) are only visible on the admin endpoint.
The admin endpoint requires a Bearer token — requests without it get 401/403.

## Running

```bash
wippy run
```

Starts HTTP server on `:8085`.

## Testing

### Public endpoint (`/api/mcp`)

```bash
# Initialize
curl -s -D - -X POST http://localhost:8085/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test"},"protocolVersion":"2025-06-18"}}'

# List tools (returns: echo, add, greet)
curl -s -X POST http://localhost:8085/api/mcp \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

### Admin endpoint (`/api/admin/mcp`)

All requests require `Authorization: Bearer secret-admin-token`.

```bash
# Without auth → 401
curl -s -X POST http://localhost:8085/api/admin/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"admin"},"protocolVersion":"2025-06-18"}}'

# Initialize (with auth)
curl -s -D - -X POST http://localhost:8085/api/admin/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret-admin-token" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"admin"},"protocolVersion":"2025-06-18"}}'

# List tools (returns: echo, add, greet, server_info, reset)
curl -s -X POST http://localhost:8085/api/admin/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret-admin-token" \
  -H "Mcp-Session-Id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# Call admin tool
curl -s -X POST http://localhost:8085/api/admin/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret-admin-token" \
  -H "Mcp-Session-Id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"reset","arguments":{"target":"cache"}}}'
```

## Tools

| Tool | Scope | Description |
|---|---|---|
| `echo` | public | Echo back the input text |
| `add` | public | Add two numbers together |
| `greet` | public | Greet someone with a style (formal, casual, pirate) |
| `server_info` | admin | Get server status and version |
| `reset` | admin | Reset application state |
