# Task Queue — REST API with Background Processing

A task management API demonstrating queue-based background processing with database persistence.
HTTP endpoints accept tasks, a memory queue dispatches them, and concurrent workers process and store
results in SQLite.

## Architecture

```
HTTP Client                    Queue                    Workers              Database
│                              │                        │                    │
│  POST /tasks                 │                        │                    │
│  {action, data}              │                        │                    │
│ ────────────────────────────▶│                        │                    │
│  202 {id, "queued"}          │  queue.publish()       │                    │
│                              │───────────────────────▶│ Worker 1           │
│                              │───────────────────────▶│ Worker 2           │
│                              │                        │  process task      │
│                              │                        │  INSERT result ───▶│
│                              │                        │  return true (ack) │
│                              │                        │                    │
│  GET /tasks                  │                        │                    │
│ ──────────────────────────────────────────────────────────────────────────▶│
│  {tasks: [...], count: N}    │                        │                    │ SELECT
```

- **POST /tasks** — validates request, generates UUID, publishes to queue, returns 202
- **Queue consumer** — 2 concurrent workers pull from the queue and process tasks
- **Workers** — execute the action (uppercase, sum, etc.), store result in SQLite
- **GET /tasks** — reads completed tasks from database, supports `?status=` filter

## Project Structure

```
14-task-queue/
├── wippy.lock
├── test.http               # REST client requests for manual testing
├── k6.js                   # k6 load test script
└── src/
    ├── _index.yaml         # db, queue, http, migration, handlers, consumer
    ├── migrate.lua         # Creates tasks table (one-shot process)
    ├── create_task.lua     # POST /tasks — queue publisher
    ├── list_tasks.lua      # GET /tasks — database reader
    └── process_task.lua    # Queue worker — processes and stores results
```

## Registry Entries

| Entry                 | Kind                  | Purpose                                  |
|-----------------------|-----------------------|------------------------------------------|
| `app:db`              | `db.sql.sqlite`       | SQLite database (in-memory)              |
| `app:queue_driver`    | `queue.driver.memory` | In-memory queue driver                   |
| `app:tasks_queue`     | `queue.queue`         | Logical queue bound to driver            |
| `app:processes`       | `process.host`        | Hosts the migration process              |
| `app:gateway`         | `http.service`        | HTTP server on :8080                     |
| `app:router`          | `http.router`         | Route dispatcher                         |
| `app:migrate`         | `process.lua`         | Migration: creates tasks table           |
| `app:migrate_service` | `process.service`     | Auto-starts migration (exits on success) |
| `app:create_task`     | `function.lua`        | POST /tasks handler                      |
| `app:list_tasks`      | `function.lua`        | GET /tasks handler                       |
| `app:process_task`    | `function.lua`        | Queue worker function                    |
| `app:task_consumer`   | `queue.consumer`      | Consumer: 2 workers, prefetch 5          |

## Running

```bash
cd examples/14-task-queue
wippy init
wippy run
```

## Testing

```bash
# Create an uppercase task
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{"action": "uppercase", "data": {"text": "hello world"}}'
# → {"id":"...","status":"queued"}

# Create a sum task
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{"action": "sum", "data": {"numbers": [1, 2, 3, 4, 5]}}'
# → {"id":"...","status":"queued"}

# List all tasks (after processing)
curl http://localhost:8080/tasks
# → {"tasks":[...], "count":2}

# Filter by status
curl "http://localhost:8080/tasks?status=completed"
```

Also available as `test.http` for REST client (VS Code, IntelliJ, etc.).

### Load Testing

```bash
k6 run k6.js
```

Two concurrent scenarios over 80 seconds:

- **blast** — `ramping-arrival-rate`: ramps 500 → 5,000 → 10,000 rps task submissions (up to 5,000 VUs)
- **readers** — `constant-arrival-rate`: 100 rps steady GET /tasks polling

Thresholds: p95 submit < 300ms, p95 list < 500ms, < 1% failures.

## Supported Actions

| Action      | Input                    | Output                    |
|-------------|--------------------------|---------------------------|
| `uppercase` | `{"text": "hello"}`      | `{"output": "HELLO"}`     |
| `sum`       | `{"numbers": [1, 2, 3]}` | `{"output": 6}`           |
| *(other)*   | any                      | `{"output": "processed"}` |

## Key Concepts

- **`queue.publish(queue_id, data)`** — publishes a message to a named queue. The data is serialized and delivered
  to a consumer worker.
- **`queue.consumer`** — entry kind that binds a queue to a handler function. `concurrency: 2` runs two parallel
  workers. `prefetch: 5` buffers up to 5 messages.
- **`queue.message()`** — accesses the current message context inside a consumer handler. Provides `id()` and
  `headers()` methods.
- **Return `true`/`false`** — returning `true` from a worker acknowledges the message (removed from queue).
  Returning `false` nacks it (requeued for retry).
- **`db.sql.sqlite`** — SQLite database entry. Using `:memory:` for this example (no persistence across restarts).
- **`sql.get(id)`** — acquires a database connection. Must call `db:release()` when done.
- **`sql.builder`** — fluent query builder: `sql.builder.select(...)`, `sql.builder.insert(...)`. Chain with
  `:from()`, `:where()`, `:order_by()`, `:limit()`, `:columns()`, `:values()`.
- **`query:run_with(db):query()`** — executes a SELECT and returns rows.
- **`query:run_with(db):exec()`** — executes INSERT/UPDATE/DELETE.
- **Migration pattern** — a `process.lua` + `process.service` that runs once on startup. Returns `0` to signal
  success; the supervisor won't restart it.
