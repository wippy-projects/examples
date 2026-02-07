# Supervision — Let It Crash

A manual supervisor spawns an unstable worker that randomly crashes (~30% chance per tick). When the worker dies, the
supervisor catches the EXIT event and restarts it with increasing backoff — up to a maximum restart count. Demonstrates
the **"let it crash"** philosophy: don't handle errors defensively, let the supervisor restart.

## Architecture

```
Terminal Host (app:terminal)
└── Supervisor (app:supervisor)
    │
    │  spawn_monitored(worker)
    │  ├── Worker ticks every 500ms
    │  │   └── ~30% chance: error("something went wrong")
    │  │
    │  ◀── EXIT event (crash detected)
    │  │
    │  │  restart += 1
    │  │  sleep(restart seconds)   ← linear backoff
    │  │  spawn_monitored(worker)  ← new worker
    │  │
    │  └── stop after 5 crashes
```

## Project Structure

```
05-supervision/
├── wippy.lock
└── src/
    ├── _index.yaml       # Registry: terminal host, process host, worker, supervisor
    ├── supervisor.lua    # Spawns worker, watches EXIT events, restarts with backoff
    └── worker.lua        # Ticks every 500ms, randomly crashes
```

## Registry Entries

| Entry                 | Kind            | Purpose                              |
|-----------------------|-----------------|--------------------------------------|
| `app:terminal`        | `terminal.host` | Terminal host (provides stdout)      |
| `app:processes`       | `process.host`  | Worker pool for spawned processes    |
| `app:unstable_worker` | `process.lua`   | Worker that randomly crashes         |
| `app:supervisor`      | `process.lua`   | Manual supervisor with restart logic |

## Running

```bash
cd examples/05-supervision
wippy init
wippy run -x app:supervisor
```

**Output:**

```
=== Supervision: Let It Crash ===

Spawning an unstable worker that randomly crashes.
Supervisor will catch EXIT events and restart it.

[supervisor] Started worker: {app:processes|0x00002}

[supervisor] Worker {app:processes|0x00002} crashed! (1/5)
[supervisor] Error: something went wrong at tick 2
[supervisor] Restarting in 1s...
[supervisor] New worker: {app:processes|0x00003}

[supervisor] Worker {app:processes|0x00003} crashed! (2/5)
[supervisor] Error: something went wrong at tick 1
[supervisor] Restarting in 2s...
...

Supervisor done. Worker crashed 5 times and was restarted each time.
In production, use process.service for declarative supervision.
```

Output varies due to randomness — the worker may survive more or fewer ticks before crashing.

## Key Concepts

- **`process.spawn_monitored(entry, host)`** — spawns a process and monitors it. The caller receives EXIT events when
  the spawned process terminates (crash or clean exit).
- **`process.events()`** — returns a channel that receives process lifecycle events. Check
  `event.kind == process.event.EXIT`
  and `event.result.error` to distinguish crashes from clean exits.
- **`error(msg)`** — Lua's built-in error throw. In Wippy, an unhandled error in a process causes the process to crash.
  The supervisor sees it as an EXIT event with `result.error` set.
- **Linear backoff** — the supervisor waits `N` seconds before the Nth restart, preventing rapid restart loops.
- **Manual vs declarative supervision** — this example shows manual supervision for learning. In production, use
  `process.service` with `lifecycle.restart` config (see [03-ping-pong](../03-ping-pong/)) for declarative supervision
  without writing restart logic.
