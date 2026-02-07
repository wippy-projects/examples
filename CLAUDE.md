# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Monorepo with Wippy runtime example projects.

## Commands

Each project is self-contained. `cd` into the project directory first.

```bash
wippy run                     # Start the HTTP server on :8080
wippy lint                    # Lint (errors + warnings)
wippy lint --level hint       # All diagnostics
wippy registry list           # List all registry entries
wippy update                  # Regenerate wippy.lock after adding files to src/
```

### Testing

```bash
# shop — full flow
curl http://localhost:8080/api/products
curl -X POST http://localhost:8080/api/cart/alice/items -H "Content-Type: application/json" -d '{"sku":"LAPTOP-001","quantity":1}'
curl http://localhost:8080/api/cart/alice
curl -X POST http://localhost:8080/api/cart/alice/checkout

# http-async-task and http-spawn
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"name":"test","duration":2}'

# Load tests (all projects have k6.js)
k6 run k6.js
```

Each project also has a `test.http` file for REST client testing.

## Architecture

### Entry System

All source lives under `src/`. The `_index.yaml` in each project declares **entries** — the fundamental unit in Wippy:

| Kind              | Purpose                                        |
|-------------------|------------------------------------------------|
| `function.lua`    | HTTP handler function (request/response)       |
| `process.lua`     | Long-running actor process with `main()`       |
| `process.host`    | Worker pool that hosts spawned processes       |
| `process.service` | Supervised process (auto-start, restart)       |
| `http.service`    | HTTP server (binds to address)                 |
| `http.router`     | Route dispatcher with path prefix              |
| `http.endpoint`   | Maps HTTP method+path to a `function.lua`      |
| `registry.entry`  | Static data stored in registry (e.g. products) |

Entries reference built-in modules via `modules:` list and other entries via `imports:` map.

### Three Concurrency Patterns

| Project            | Pattern                 | Key API                                          | When to use                                              |
|--------------------|-------------------------|--------------------------------------------------|----------------------------------------------------------|
| `http-async-task/` | Background coroutine    | `coroutine.spawn(fn)`                            | Lightweight fire-and-forget, shared memory               |
| `http-spawn/`      | Dedicated actor process | `process.spawn(entry, host, arg)`                | Isolated state, supervision, independent lifecycle       |
| `shop/`            | Actor-per-user + events | `process.spawn` + `process.send` + `events.send` | Stateful per-entity processes, event-driven side effects |

### Shop-Specific: Request-Reply Between HTTP Handler and Process

```
HTTP Handler ──process.send(pid, topic, data)──▶ Cart Process
             ◀──process.send(sender, reply_topic, data)──┘
```

The handler uses `process.inbox()` + `channel.select` with `time.after()` timeout to wait for the reply.

## Known Gotchas

See [QA.md](QA.md) for detailed diagnosis and fixes. Summary:

- **`res:set_status(N):write_json(...)` does NOT work** — `set_status()` doesn't return `res`. Use separate calls.
- **`msg:payload()` returns userdata**, not a table — call `msg:payload():data()` to unwrap.
- **PID objects don't survive `process.send()` serialization** — use `tostring(process.pid())` or `msg:from()`.
- **`process.listen(topic)` is for pubsub**, not inbox — use `process.inbox()` for point-to-point replies.
- **`registry.find({kind = "..."})`** warns about `meta.` prefix — use `registry.find({["meta.type"] = "product"})`.

Add to this list as you encounter issues!

## Wippy Documentation

- Docs: https://home.wj.wippy.ai/
- LLM index: https://home.wj.wippy.ai/llms.txt
- Batch fetch: `https://home.wj.wippy.ai/llm/context?paths=<comma-separated-paths>`
- Search: `https://home.wj.wippy.ai/llm/search?q=<query>`
