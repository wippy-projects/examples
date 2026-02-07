# Worker Pool — Channels + Coroutines

A single process spawns 3 worker coroutines that pull jobs from a shared channel, process them in parallel, and push
results to a results channel. Demonstrates **fan-out** (distribute work) and **fan-in** (collect results) — all within
one process using channels to coordinate coroutines.

## Architecture

```
Process (app:pool)
│
│  jobs channel ──────────────────▶ Worker 1 ──┐
│  (buffered, 10 slots)           ▶ Worker 2 ──┤──▶ results channel
│                                 ▶ Worker 3 ──┘    (buffered, 10 slots)
│
│  send 10 jobs → close(jobs) → collect 10 results → done
```

Workers run as coroutines inside the same process. They share no state — all coordination happens through channels.

## Project Structure

```
04-worker-pool/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: terminal host + pool process
    └── pool.lua        # main() → spawn workers → fan-out/fan-in → exit
```

## Registry Entries

| Entry          | Kind            | Purpose                           |
|----------------|-----------------|-----------------------------------|
| `app:terminal` | `terminal.host` | Terminal host (provides stdout)   |
| `app:pool`     | `process.lua`   | Worker pool process with `main()` |

## Running

```bash
cd examples/04-worker-pool
wippy run -x app:pool
```

**Output:**

```
=== Worker Pool: Channels + Coroutines ===

Spawned 3 workers
Sending 10 jobs...

  Job #3: 3^2 = 9  (worker 3)
  Job #1: 1^2 = 1  (worker 1)
  Job #2: 2^2 = 4  (worker 2)
  Job #6: 6^2 = 36  (worker 1)
  Job #4: 4^2 = 16  (worker 3)
  Job #5: 5^2 = 25  (worker 2)
  ...

All jobs done. Workers shared a channel, no shared state.
```

Jobs arrive out of order because 3 workers process them concurrently (each job takes 200ms).

## Key Concepts

- **`channel.new(size)`** — creates a buffered channel. Channels are typed queues that coroutines use to communicate.
  `send()` blocks when full, `receive()` blocks when empty.
- **`coroutine.spawn(fn)`** — runs a function as a lightweight coroutine inside the same process. No separate actor, no
  serialization overhead — coroutines share the process memory.
- **`channel:close()`** — signals no more values will be sent. Workers detect this when `receive()` returns `nil, false`
  and exit their loop.
- **Fan-out / Fan-in** — a classic concurrency pattern. One producer sends jobs to a shared channel (fan-out to
  workers), workers send results to a results channel (fan-in to collector).
- **Coroutines vs Processes** — coroutines are lightweight (shared memory, no serialization) but have no isolation or
  supervision. Use coroutines for parallel work within a single task; use processes when you need isolation, independent
  lifecycle, or restart logic.
