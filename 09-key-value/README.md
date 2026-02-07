# Key-Value Store — Process State + Request/Reply

An in-memory key-value store implemented as a long-running process. State lives entirely in process memory — no external
storage. A CLI client sends commands (set/get/delete/keys/stats) via messages and waits for replies. Demonstrates the
request/reply pattern with `process.send()` + `process.inbox()`.

## Architecture

```
CLI (client)                           KV Server (process.service)
│                                      │  data = {}
│  send("kv", "set", {key, value})     │
│ ────────────────────────────────────▶ │  data[key] = value
│                                      │  send(reply_to, "kv_response", {ok: true})
│ ◀──────────────────────────────────── │
│                                      │
│  send("kv", "get", {key})            │
│ ────────────────────────────────────▶ │  value = data[key]
│                                      │  send(reply_to, "kv_response", {value, found})
│ ◀──────────────────────────────────── │
│                                      │
│  send("kv", "keys", {})              │
│ ────────────────────────────────────▶ │  collect all keys
│                                      │  send(reply_to, "kv_response", {keys, count})
│ ◀──────────────────────────────────── │
```

The KV server registers itself as `"kv"` in the process registry. The CLI sends to `"kv"` by name — no PID lookup
needed. Each request includes `reply_to` (the CLI's PID as a string) so the server knows where to send the response.

## Project Structure

```
09-key-value/
├── wippy.lock
└── src/
    ├── _index.yaml        # Registry: terminal host, process host, KV service, CLI
    ├── kv_server.lua      # KV store process: handles set/get/delete/keys/stats
    └── cli.lua            # Client: sends commands, displays results
```

## Registry Entries

| Entry                   | Kind              | Purpose                         |
|-------------------------|-------------------|---------------------------------|
| `app:terminal`          | `terminal.host`   | Terminal host (provides stdout) |
| `app:processes`         | `process.host`    | Worker pool for processes       |
| `app:kv_server`         | `process.lua`     | KV store process implementation |
| `app:kv_server.service` | `process.service` | Auto-starts the KV server       |
| `app:cli`               | `process.lua`     | Client CLI (entry point)        |

## Running

```bash
cd examples/09-key-value
wippy init
wippy run -x app:cli
```

**Output:**

```
=== Key-Value Store as a Process ===

Setting values:
  SET name = Wippy  → ok: true
  SET version = 0.1  → ok: true
  SET lang = Lua  → ok: true
  SET model = Actor  → ok: true
  SET overhead = 13KB  → ok: true

Getting values:
  GET name → Wippy
  GET version → 0.1
  GET lang → Lua
  GET missing_key → (not found)

Deleting 'lang':
  Deleted: true

Listing all keys:
  Keys (4): version, overhead, name, model

Server stats:
  Total operations: 12
  Total keys: 4

The KV store is a process. State lives in memory.
No database, no disk — just actor state + messages.
```

## Supported Operations

| Topic    | Payload        | Response                               |
|----------|----------------|----------------------------------------|
| `set`    | `{key, value}` | `{op: "set", key, ok: true}`           |
| `get`    | `{key}`        | `{op: "get", key, value, found}`       |
| `delete` | `{key}`        | `{op: "delete", key, deleted}`         |
| `keys`   | `{}`           | `{op: "keys", keys, count}`            |
| `stats`  | `{}`           | `{op: "stats", total_ops, total_keys}` |

## Key Concepts

- **Process as state container** — the KV server's `data` table lives in process memory. No shared state, no locks —
  the process handles one message at a time.
- **`process.registry.register("kv")`** — registers the server under a name so clients can send to `"kv"` directly
  instead of needing the PID.
- **Request/reply pattern** — each request includes `reply_to = tostring(process.pid())`. The server sends the response
  back to that PID. The client waits on `process.inbox()` with a timeout.
- **`process.service`** — the KV server is declared as a `process.service` with `auto_start: true`, so it starts
  automatically when `wippy run` launches.
- **`msg:payload():data()`** — always unwrap message payloads to get the Lua table.
- **`tostring(process.pid())`** — PID userdata doesn't survive serialization through `process.send()`. Convert to
  string before including in message payloads.
- **`channel.select`** — used with `inbox:case_receive()` and `events:case_receive()` for multiplexed message handling,
  and with `time.after()` for timeouts.
