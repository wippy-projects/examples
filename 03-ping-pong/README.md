# Ping-Pong — Two Services Exchanging Messages

Two auto-started services — a **pinger** and a **ponger** — continuously exchange messages. Demonstrates supervised
services, process registry for discovery, and inbox messaging between actors.

## Architecture

```
Process Host (app:processes)
├── Ponger (service, auto-start)         Pinger (service, auto-start)
│   registry.register("ponger")          ponger = registry.lookup("ponger")
│                                        │
│   while true:                          while true:
│     msg = inbox:receive()                send(ponger, "ping", {round})
│     if "ping" →                          wait for "pong" (3s timeout)
│       send(from, "pong")                 sleep 1s
```

Ponger registers itself in the process registry. Pinger polls the registry until ponger is found, then starts the
ping/pong loop. Both run forever until the runtime is terminated.

## Project Structure

```
03-ping-pong/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: process host + 2 services
    ├── pinger.lua      # Sends "ping", waits for "pong", repeats every 1s
    └── ponger.lua      # Receives "ping", replies "pong"
```

## Registry Entries

| Entry                | Kind              | Purpose                               |
|----------------------|-------------------|---------------------------------------|
| `app:processes`      | `process.host`    | Worker pool for both services         |
| `app:ponger_process` | `process.lua`     | Ponger process definition             |
| `app:ponger`         | `process.service` | Supervised ponger (auto-start)        |
| `app:pinger_process` | `process.lua`     | Pinger process definition             |
| `app:pinger`         | `process.service` | Supervised pinger (auto-start)        |

## Running

```bash
cd examples/03-ping-pong
wippy run
```

Ctrl+C to stop.

**Logs:**

```
INFO  Ponger ready             {"pid": "{app:processes|0x00003}"}
INFO  Pinger found ponger      {"ponger": "{app:processes|0x00003}"}
INFO  Pinger sent ping         {"round": 1}
INFO  Ponger received ping     {"round": 1}
INFO  Pinger received pong     {"round": 1}
INFO  Pinger sent ping         {"round": 2}
INFO  Ponger received ping     {"round": 2}
INFO  Pinger received pong     {"round": 2}
...
```

## Message Flow

```
Pinger                              Ponger
  │                                   │  registry.register("ponger")
  │  registry.lookup("ponger")        │
  │                                   │
  │  send(ponger, "ping", {round=1})  │
  │ ─────────────────────────────────▶│
  │                 send(from, "pong") │
  │◀───────────────────────────────── │
  │  sleep 1s                         │
  │                                   │
  │  send(ponger, "ping", {round=2})  │
  │ ─────────────────────────────────▶│
  │                 send(from, "pong") │
  │◀───────────────────────────────── │
  │  ... repeats forever ...          │
```

## Key Concepts

- **`process.service`** — a supervised process that auto-starts with the runtime. Defined as a wrapper around a
  `process.lua` entry, specifying which host to run on.
- **`process.registry.register(name, pid)` / `process.registry.lookup(name)`** — named process discovery. A process
  registers itself under a string name; others find it by that name.
- **`msg:from()`** — returns the sender's PID as a string. Ponger uses this to reply without the sender needing to
  include its PID in the payload.
- **`process.inbox()` + `channel.select`** — the inbox receives point-to-point messages. Combined with `time.after()`
  for timeout-guarded waits.
- **`msg:payload():data()`** — always unwrap message payloads. The raw `msg:payload()` is userdata, not a Lua table.
- **Startup ordering** — services may start in any order. Pinger handles this by polling `registry.lookup()` until
  ponger is registered.
