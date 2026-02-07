# HTTP Spawn — Process-Per-Task Pattern

HTTP server that accepts `POST /api/tasks` and spawns a **dedicated actor process** for each task. Each process runs in
isolation with its own state, executes the work, and exits — freeing memory automatically.

## Architecture

```
Client                    Handler (function)          Worker Process (actor)
  │                            │                              │
  │  POST /api/tasks           │                              │
  │  {"name":"report"}         │                              │
  │ ──────────────────────────▶│                              │
  │                            │  process.spawn(worker, task) │
  │                            │ ────────────────────────────▶│ [PID created]
  │          202 Accepted      │                              │
  │ ◀──────────────────────────│                              │  step 1/3...
  │                                                           │  step 2/3...
  │                                                           │  step 3/3...
  │                                                           │  return 0 → dies ✓
  │                                                           │  [memory freed]
```

Unlike `coroutine.spawn()`, each task here gets its own **isolated process** (actor). The process has private memory,
can be monitored, and is managed by the scheduler independently. When it finishes (`return 0`), the process dies and
memory is freed.

## Project Structure

```
http-spawn/
├── wippy.lock
├── k6.js              # Load test
├── test.http           # Manual test requests
└── src/
    ├── _index.yaml     # Registry: http server + handler + worker
    ├── handler.lua     # POST /api/tasks → process.spawn → 202
    └── worker.lua      # Worker process: runs task, exits
```

## Registry Entries

| Entry                      | Kind            | Purpose                   |
|----------------------------|-----------------|---------------------------|
| `app:processes`            | `process.host`  | Process host (8 workers)  |
| `app:gateway`              | `http.service`  | HTTP server on `:8080`    |
| `app:router`               | `http.router`   | Router with `/api` prefix |
| `app:task_worker`          | `process.lua`   | Worker process definition |
| `app:submit_task`          | `function.lua`  | HTTP handler function     |
| `app:submit_task.endpoint` | `http.endpoint` | `POST /api/tasks`         |

## API

### POST /api/tasks

Submit a task — spawns a new worker process.

**Request:**

```json
{
  "name": "generate-report",
  "duration": 5
}
```

| Field      | Type    | Required | Description                      |
|------------|---------|----------|----------------------------------|
| `name`     | string  | yes      | Task name (non-empty)            |
| `duration` | integer | no       | Duration in seconds (default: 3) |

**Response `202 Accepted`:**

```json
{
  "pid": "abc123",
  "name": "generate-report",
  "status": "spawned",
  "message": "Process abc123 will run for 5 seconds"
}
```

**Errors:**

- `400` — Invalid JSON or missing `name`

## Running

```bash
cd examples/http-spawn
wippy run
```

## Testing

### Manual

```bash
# Spawn three worker processes simultaneously
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"name": "alpha", "duration": 5}'
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"name": "beta", "duration": 3}'
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"name": "gamma", "duration": 7}'
```

Each request returns immediately with a PID. Watch the logs — you'll see three independent processes working in
parallel, each finishing and exiting on its own schedule.

### Load test

```bash
k6 run k6.js
```

## How It Works

1. HTTP handler receives request, validates input
2. `process.spawn("app:task_worker", "app:processes", task)` creates a new actor
3. Handler returns `202` with the PID immediately
4. Worker process receives `task` as argument, simulates work step by step
5. Worker returns `0` (clean exit) — process dies, memory is freed
6. Supervisor does NOT restart it (normal exit code)

## Coroutine vs Process Spawn

|                  | `coroutine.spawn`           | `process.spawn`                     |
|------------------|-----------------------------|-------------------------------------|
| **Isolation**    | Shares process memory       | Own isolated memory                 |
| **Overhead**     | Minimal                     | ~13 KB per process                  |
| **Supervision**  | None                        | Can be monitored/linked             |
| **Crash impact** | Affects host process        | Isolated — only this actor dies     |
| **Best for**     | Lightweight fire-and-forget | Tasks needing isolation, monitoring |

See [http-async-task](../http-async-task/) for the coroutine approach.
