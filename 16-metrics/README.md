# Metrics & Telemetry — Instrumenting Apps with the `metrics` Module

An HTTP service that tracks orders and demonstrates all three metric types: counters, gauges, and histograms. Also
shows runtime statistics via the `system` module.

## Architecture

```
HTTP Client
├── POST /api/orders  → create_order handler
│   ├── metrics.counter_inc("orders_total")
│   ├── metrics.counter_add("revenue_total", price * amount)
│   ├── metrics.counter_add("items_sold_total", amount)
│   ├── metrics.gauge_inc/dec("orders_pending")
│   └── metrics.histogram("request_duration_seconds", elapsed)
├── GET  /api/stats   → get_stats handler
│   ├── system.memory.stats()
│   └── system.runtime.goroutines()
└── GET  /api/health  → health check
```

## Project Structure

```
16-metrics/
├── wippy.lock
└── src/
    ├── _index.yaml
    └── handlers/
        ├── create_order.lua    # Order endpoint with full metric instrumentation
        ├── get_stats.lua       # Runtime memory and goroutine statistics
        └── health.lua          # Simple health check
```

## Running

```bash
cd examples/16-metrics
wippy run
```

## Testing

```bash
# Health check
curl http://localhost:8080/api/health

# Create orders (generates counter + histogram metrics)
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{"item":"laptop","amount":2,"price":999.99}'

# Error case (increments error counter)
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{}'

# Runtime statistics (memory, goroutines)
curl http://localhost:8080/api/stats
```

## Metric Types

| Type      | Function                                              | Use Case                                                 |
|-----------|-------------------------------------------------------|----------------------------------------------------------|
| Counter   | `counter_inc(name, labels)`                           | Monotonically increasing values (requests, errors)       |
| Counter   | `counter_add(name, value, labels)`                    | Add arbitrary amounts (revenue, bytes)                   |
| Gauge     | `gauge_set(name, value, labels)`                      | Point-in-time values (queue depth, temperature)          |
| Gauge     | `gauge_inc(name, labels)` / `gauge_dec(name, labels)` | Increment/decrement (active connections)                 |
| Histogram | `histogram(name, value, labels)`                      | Distribution of values (request duration, response size) |

All functions return `boolean, error` and accept an optional labels table.

## Key Concepts

- **`metrics` module** — must be listed in the entry's `modules:` array
- **Labels** — key-value pairs for metric dimensions (e.g., `{method = "POST", status = "ok"}`)
- **`system` module** — exposes `system.memory.stats()` and `system.runtime.goroutines()` for runtime introspection
- **`time.now()` + `:sub()`** — measure elapsed duration for histograms via `elapsed:seconds()`
- **Prometheus** — enable in `.wippy.yaml` config to expose metrics at `/metrics` for scraping

## Wippy Documentation

- Metrics module: https://home.wj.wippy.ai/en/lua/system/metrics
- Observability guide: https://home.wj.wippy.ai/en/guides/observability
- Configuration: https://home.wj.wippy.ai/en/guides/configuration
