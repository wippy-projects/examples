# HTTP Async Task — Coroutine Background Processing

HTTP server that accepts `POST /api/tasks`, validates input, and runs a background task via `coroutine.spawn()`. Returns
`202 Accepted` immediately while the coroutine continues working.

## Architecture

```
Client                    Handler (function)              Coroutine
  │                            │                              │
  │  POST /api/tasks           │                              │
  │  {"name":"report"}         │                              │
  │ ──────────────────────────▶│                              │
  │                            │  coroutine.spawn(work)       │
  │                            │ ────────────────────────────▶│
  │          202 Accepted      │                              │  step 1/3...
  │ ◀──────────────────────────│                              │  step 2/3...
  │                                                           │  step 3/3...
  │                                                           │  done ✓
```

`coroutine.spawn()` runs a background coroutine **inside** the same process as the HTTP handler. It's lightweight — no
overhead of creating a separate actor. Good for fire-and-forget tasks that don't need state isolation.

## Project Structure

```
http-async-task/
├── wippy.lock
├── k6.js              # Load test
├── test.http           # Manual test requests
└── src/
    ├── _index.yaml     # Registry: http server + handler
    └── handler.lua     # POST /api/tasks → coroutine.spawn → 202
```

## Registry Entries

| Entry                       | Kind            | Purpose                   |
|-----------------------------|-----------------|---------------------------|
| `app:processes`             | `process.host`  | Process host (4 workers)  |
| `app:gateway`               | `http.service`  | HTTP server on `:8080`    |
| `app:router`                | `http.router`   | Router with `/api` prefix |
| `app:process_task`          | `function.lua`  | Task handler function     |
| `app:process_task.endpoint` | `http.endpoint` | `POST /api/tasks`         |

## API

### POST /api/tasks

Submit a background task.

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
  "task_id": "task_1738880000",
  "name": "generate-report",
  "status": "accepted",
  "message": "Task will run for 5 seconds in background"
}
```

**Errors:**

- `400` — Invalid JSON or missing `name`

## Running

```bash
cd examples/http-async-task
wippy run
```

## Testing

### Manual

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"name": "generate-report", "duration": 5}'
```

Watch the logs — you'll see step-by-step progress while the HTTP response was already returned.

### Load test

```bash
k6 run k6.js
```

## When to Use `coroutine.spawn`

| Good fit                           | Not a good fit                         |
|------------------------------------|----------------------------------------|
| Lightweight fire-and-forget tasks  | Tasks needing isolated state           |
| Logging, metrics emission          | Tasks requiring monitoring/supervision |
| Processing within the same process | Tasks with retry/restart logic         |
| Minimal overhead needed            | Tasks with independent lifecycle       |

For isolated tasks with supervision, use `process.spawn()` — see the [http-spawn](../http-spawn/) example.
