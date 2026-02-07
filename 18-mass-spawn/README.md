# Mass Spawn — 10000 Long-Lived Processes with Periodic Ticking

Spawns 10000 concurrent processes that each run a `while true` loop with a periodic ticker,
sending "tick" messages back to a central spawner. Demonstrates that Wippy processes are lightweight
(~13KB each) and the scheduler efficiently multiplexes thousands across a small worker pool.

## Architecture

```
Process Host (app:processes, 32 workers)
└── Spawner Service (app:spawner)  ← process.service, auto-start
    │
    │  1. Spawn NUM_WORKERS processes at startup
    │  2. Each worker ticks every 500ms–3s (random per worker)
    │  3. Spawner collects "tick" messages and prints stats every 2s
    │
    │  channel.select:
    │    ├── events   → EXIT (alive--) or CANCEL (shutdown)
    │    ├── inbox    → "tick" messages from workers
    │    └── ticker   → print stats every 2s
    │
    ├── Worker 1    →  while true: sleep(random), send "tick", repeat
    ├── Worker 2    →  while true: sleep(random), send "tick", repeat
    ├── Worker 3    →  while true: sleep(random), send "tick", repeat
    │   ...
    └── Worker 1000 →  while true: sleep(random), send "tick", repeat
```

Each worker is a separate process with its own event loop (`while true` + `channel.select`).
Workers tick at random intervals and report back to the spawner via `process.send()`.
The spawner monitors all workers via `process.spawn_monitored()` and tracks EXIT events.

## Project Structure

```
18-mass-spawn/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: host, env vars, spawner service, worker
    ├── spawner.lua     # main() → spawn N workers, collect ticks, print stats
    └── worker.lua      # main(pid, id, interval) → while loop with ticker
```

## Running

```bash
cd examples/18-mass-spawn
wippy init
wippy run
```

Press **Ctrl+C** to stop gracefully.

**Expected Output:**

```
INFO  mass spawn starting  {"num_workers": 10000, "tick_min_ms": 500, "tick_max_ms": 3000, ...}
INFO  all workers spawned  {"count": 10000, "elapsed_s": 0.027}
INFO  stats                {"alive": 10000, "total_ticks": 847, "new_ticks": 847, "tick_rate": 423}
INFO  stats                {"alive": 10000, "total_ticks": 2309, "new_ticks": 1462, "tick_rate": 577}
INFO  stats                {"alive": 10000, "total_ticks": 3774, "new_ticks": 1465, "tick_rate": 629}
^C
INFO  shutting down         {"workers_spawned": 1000, "still_alive": 1000, "total_ticks": 6507, ...}
```

### Configuring via Environment Variables

```bash
# Fewer workers, faster ticking
NUM_WORKERS=100 TICK_MIN=100ms TICK_MAX=500ms wippy run

# Stress test: 5000 workers
NUM_WORKERS=5000 TICK_MIN=1s TICK_MAX=5s wippy run

# Gentle mode: few workers, slow ticks
NUM_WORKERS=50 TICK_MIN=5s TICK_MAX=10s STATS_INTERVAL=5s wippy run
```

## Registry Entries

| Entry                 | Kind              | Purpose                                            |
|-----------------------|-------------------|----------------------------------------------------|
| `app:processes`       | `process.host`    | Worker pool (32 goroutines, queue 4096)            |
| `app:os_env`          | `env.storage.os`  | OS environment access                              |
| `app:num_workers`     | `env.variable`    | NUM_WORKERS — number of processes (default: 10000) |
| `app:tick_min`        | `env.variable`    | TICK_MIN — min tick interval (default: "500ms")    |
| `app:tick_max`        | `env.variable`    | TICK_MAX — max tick interval (default: "3s")       |
| `app:stats_interval`  | `env.variable`    | STATS_INTERVAL (default: "2s")                     |
| `app:spawner_process` | `process.lua`     | Spawner logic                                      |
| `app:spawner`         | `process.service` | Supervised spawner (auto-start, restarts)          |
| `app:worker`          | `process.lua`     | Worker — while loop with periodic ticker           |

## Key Concepts

- **Long-lived processes** — each worker runs a `while true` event loop with `channel.select`,
  ticking at a random interval and reporting back to the spawner. They run until CANCEL.

- **Lightweight processes** — each Wippy process has ~13KB baseline overhead. 1000 concurrent
  processes ~ 13MB. This makes "one process per task" practical.

- **Work-stealing scheduler** — the process host runs 32 worker goroutines. When a process yields
  (e.g., waiting on `channel.select`), the worker picks up another process.

- **`process.spawn_monitored()`** — spawns a child process and monitors it. EXIT events are
  delivered to the spawner's event channel when a worker exits or crashes.

- **`channel.select` multiplexing** — both the spawner and workers use `channel.select` to
  wait on multiple channels simultaneously (events, inbox, ticker).

- **`logger` module** — structured logging that works in `process.service` context (unlike
  `io.print` which requires a terminal host with `-x` execution).

- **`process.service` with auto_start** — the spawner runs as a supervised service. If it
  crashes, the supervisor restarts it with exponential backoff.

- **Environment-based configuration** — all tuning knobs are `env.variable` entries with
  sensible defaults. Override via OS environment without touching code.

## Memory Estimate

| NUM_WORKERS | Approx Memory |
|-------------|---------------|
| 100         | ~1.3 MB       |
| 1,000       | ~13 MB        |
| 5,000       | ~65 MB        |
| 10,000      | ~130 MB       |

Actual numbers depend on per-process state and message buffers.
