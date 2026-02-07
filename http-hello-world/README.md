# HTTP Hello World

Your first Wippy HTTP application — a minimal web API with one endpoint.

```
GET /hello → {"message": "hello world"}
```

## Architecture

```
HTTP request
│
▼
gateway (http.service :8080)
│
▼
api (http.router, prefix: /)
│
▼
hello.endpoint (GET /hello)
│
▼
hello (function.lua) → {"message": "hello world"}
```

Four entries work together:

1. **`gateway`** — HTTP server listening on port 8080
2. **`api`** — Router attached to gateway via `meta.server`
3. **`hello`** — Lua function that handles requests
4. **`hello.endpoint`** — Routes `GET /hello` to the function

## Project Structure

```
http-hello-world/
├── wippy.lock
└── src/
    ├── _index.yaml      # 4 entries: server, router, function, endpoint
    └── hello.lua         # Handler: returns JSON
```

## Registry Entries

| Entry               | Kind            | Purpose                         |
|---------------------|-----------------|---------------------------------|
| `app:gateway`       | `http.service`  | HTTP server on :8080            |
| `app:api`           | `http.router`   | Route dispatcher (prefix: `/`)  |
| `app:hello`         | `function.lua`  | Handler function                |
| `app:hello.endpoint`| `http.endpoint` | Maps `GET /hello` to handler    |

## Running

```bash
cd examples/http-hello-world
wippy run
```

Test:

```bash
curl http://localhost:8080/hello
```

Response:

```json
{"message":"hello world"}
```

## Key Concepts

- **`http.service`** — declares an HTTP server with an address. `auto_start: true` starts it with `wippy run`.
- **`http.router`** — attaches to a server via `meta.server: gateway`. Routes requests by path prefix.
- **`http.endpoint`** — maps an HTTP method + path to a `function.lua` handler. Links to router via `meta.router`.
- **`function.lua`** — stateless handler. Uses `http.response()` to build the response. No request parsing needed for
  this simple case.
- **`res:set_status()` then `res:write_json()`** — response methods must be called separately (chaining doesn't work
  because `set_status()` doesn't return `res`).
