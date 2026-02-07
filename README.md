# Wippy Examples

Three example projects demonstrating Wippy runtime patterns.

## Examples

| Project | Description | Patterns |
|---------|-------------|----------|
| [shop/](shop/) | Shopping cart API with per-user actor processes | HTTP endpoints, process spawn, message passing, event bus |
| [http-async-task/](http-async-task/) | Background task via coroutine | HTTP endpoint, `coroutine.spawn` |
| [http-spawn/](http-spawn/) | Background task via dedicated process | HTTP endpoint, `process.spawn` |

## Prerequisites

Install the Wippy CLI: https://wippy.ai

## Running

Each example is a standalone project. `cd` into the directory and run:

```bash
wippy run
```

The server starts on `:8080` by default.

## Testing

### shop

```bash
# List products
curl http://localhost:8080/api/products

# Add item to cart
curl -X POST http://localhost:8080/api/cart/alice/items \
  -H "Content-Type: application/json" \
  -d '{"sku":"LAPTOP-001","quantity":1}'

# View cart
curl http://localhost:8080/api/cart/alice

# Checkout (triggers delivery + email events)
curl -X POST http://localhost:8080/api/cart/alice/checkout

# Full test script is in shop/test.http
```

### http-async-task

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"name":"my-task","duration":3}'
```

### http-spawn

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"name":"my-task","duration":3}'
```

## Linting

```bash
wippy lint                # Errors and warnings
wippy lint --level hint   # All diagnostics
```

## Other Useful Commands

```bash
wippy registry list       # List all registry entries
wippy update              # Regenerate wippy.lock
wippy install             # Install dependencies
```

## Troubleshooting

See [QA.md](QA.md) for common issues and solutions.
