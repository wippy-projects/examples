# Echo Service — Distributed Message Processing

A distributed echo service demonstrating process spawning, message passing, channels, coroutines, and monitoring. A CLI
client sends messages to a relay service, which spawns a short-lived worker for each message. The worker uppercases the
text and replies directly to the client.

## Architecture

```
CLI Process                    Relay Process                  Workers
│                              │  process.registry("relay")   │
│  send("relay", "echo", msg)  │                              │
│ ────────────────────────────▶│                              │
│                              │  spawn_monitored(worker)     │
│                              │─────────────────────────────▶│ Worker 1
│                              │                              │  HELLO WORLD
│◀────────────────────────────────────────────────────────────│  send(sender, "echo_response")
│                              │                              │  exit(0)
│                              │  EXIT event ◀────────────────│
│                              │                              │
│  send("relay", "echo", msg)  │                              │
│ ────────────────────────────▶│  spawn_monitored(worker)     │
│                              │─────────────────────────────▶│ Worker 2
│◀────────────────────────────────────────────────────────────│  ...
│                              │                              │
│                              │  coroutine: stats every 5s   │
```

- **CLI** sends to `"relay"` by registered name, waits for reply with timeout
- **Relay** is a long-running service that spawns a monitored worker per message
- **Workers** are short-lived — process one message and exit
- A **stats coroutine** in the relay reports message/worker counts every 5 seconds

## Project Structure

```
13-echo-service/
├── wippy.lock
└── src/
    ├── _index.yaml       # terminal, process host, relay service, worker, CLI
    ├── relay.lua          # Relay: registry, spawn workers, stats coroutine
    ├── worker.lua         # Worker: uppercase + reply, then exit
    └── cli.lua            # CLI: interactive input, send/receive with timeout
```

## Registry Entries

| Entry               | Kind              | Purpose                               |
|---------------------|-------------------|---------------------------------------|
| `app:terminal`      | `terminal.host`   | Terminal host (provides stdin/stdout) |
| `app:processes`     | `process.host`    | Worker pool for relay and workers     |
| `app:relay`         | `process.lua`     | Relay process implementation          |
| `app:relay-service` | `process.service` | Auto-starts the relay                 |
| `app:worker`        | `process.lua`     | Worker process (spawned per message)  |
| `app:cli`           | `process.lua`     | Interactive CLI client                |

## Running

```bash
cd examples/13-echo-service
wippy init
wippy run -x app:cli
```

**Output:**

```
Echo Client
Type messages to echo. Ctrl+C to exit.

> hello world
  HELLO WORLD
  from worker: {app:processes|0x00004}

> wippy is great
  WIPPY IS GREAT
  from worker: {app:processes|0x00006}

Goodbye!
```

## Key Concepts

- **`process.spawn_monitored(entry, host, ...args)`** — spawns a child process and monitors it. When the child exits,
  the parent receives an `EXIT` event via `process.events()`. Arguments are passed to `main(...)`.
- **Short-lived workers** — each worker handles exactly one message and exits. The relay tracks worker lifecycle via
  EXIT events. This is the "one process per task" pattern.
- **`coroutine.spawn(fn)`** — runs a function concurrently within the same process, sharing memory. The stats reporter
  coroutine sleeps for 5 seconds and logs counts. Coroutines yield at I/O operations like `time.sleep()`.
- **`process.registry.register("relay")`** — the relay registers by name so the CLI can send to `"relay"` without
  knowing the PID.
- **Request/reply with timeout** — the CLI sends via `process.send("relay", "echo", msg)` with its PID in the payload.
  The worker replies directly to the sender. The CLI waits with `time.after("2s")` timeout.
- **`tostring(process.pid())`** — PID userdata doesn't survive serialization. The sender PID is converted to a string
  before including in the message payload.
