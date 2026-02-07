# Pipeline — Process Chain

A 4-stage data processing pipeline where each stage is an isolated process. Raw log lines flow through a **parser**,
**transformer**, **JSON formatter**, and **aggregator**, with the final summary returned to the orchestrator.
Demonstrates chaining processes via message passing — each stage only knows the next stage's PID.

## Architecture

```
CLI (orchestrator)
│
│  "INFO|user.login|Alice"
│  ──────────────────────▶ Parser (stage 1)
│                          split "LEVEL|type|user"
│                          ──────────────────────▶ Transformer (stage 2)
│                                                  add severity score
│                                                  normalize fields
│                                                  ──────────────────▶ Formatter (stage 3)
│                                                                      json.encode → json.decode
│                                                                      ──────────────────▶ Aggregator (stage 4)
│                                                                                          count by type/user
│                                                                                          track max severity
│  ◀──────────────────────────────────────────────────────────────────────────────────────
│  summary: {total: 10, max_severity: 4, by_type: {...}, by_user: {...}}
```

Stages are spawned in reverse order so each receives the next stage's PID as an argument.

## Project Structure

```
08-pipeline/
├── wippy.lock
└── src/
    ├── _index.yaml        # Registry: terminal host, process host, 5 processes
    ├── cli.lua            # Orchestrator: spawns pipeline, feeds data, collects results
    ├── parser.lua         # Stage 1: parse "LEVEL|type|user" into structured data
    ├── transformer.lua    # Stage 2: normalize level, add severity score
    ├── formatter.lua      # Stage 3: encode to JSON and decode back
    └── aggregator.lua     # Stage 4: count events, send summary back
```

## Registry Entries

| Entry             | Kind            | Purpose                          |
|-------------------|-----------------|----------------------------------|
| `app:terminal`    | `terminal.host` | Terminal host (provides stdout)  |
| `app:processes`   | `process.host`  | Worker pool for pipeline stages  |
| `app:parser`      | `process.lua`   | Stage 1: parse raw log lines     |
| `app:transformer` | `process.lua`   | Stage 2: enrich with severity    |
| `app:formatter`   | `process.lua`   | Stage 3: JSON encode/decode      |
| `app:aggregator`  | `process.lua`   | Stage 4: aggregate and summarize |
| `app:cli`         | `process.lua`   | Orchestrator (CLI entry point)   |

## Running

```bash
cd examples/08-pipeline
wippy init
wippy run -x app:cli
```

**Output:**

```
=== Pipeline: Process Chain ===

Data flows through 4 processes:
  Parser → Transformer → Formatter → Aggregator

Feeding 10 log lines into pipeline:

  → INFO|user.login|Alice
  → INFO|user.login|Bob
  → WARN|user.failed_login|Charlie
  ...

Waiting for aggregated results...

=== Summary ===
Total events: 10
Max severity: 4

By event type:
  user.login: 3
  page.view: 2
  ...

By user:
  alice: 4
  bob: 3
  charlie: 2
  system: 1

Each stage was an isolated process. Data flowed via messages.
```

## Data Flow

Each stage receives messages on its inbox, processes them, and forwards to the next stage:

| Stage       | Input Topic | Processing                              | Output Topic |
|-------------|-------------|-----------------------------------------|--------------|
| Parser      | `raw_line`  | Split `"LEVEL\|type\|user"` into fields | `parsed`     |
| Transformer | `parsed`    | Normalize level, compute severity score | `enriched`   |
| Formatter   | `enriched`  | `json.encode()` → `json.decode()`       | `formatted`  |
| Aggregator  | `formatted` | Count by type/user, track max severity  | `summary`    |

A `done` message flows through all stages to signal end-of-data. The aggregator sends the final summary back to the CLI.

## Key Concepts

- **Process pipeline** — each stage is a `process.lua` spawned with the next stage's PID. Data flows forward via
  `process.send()`, results flow back to the orchestrator.
- **`json.encode()` / `json.decode()`** — the `json` module serializes Lua tables to JSON strings and back. The
  formatter stage demonstrates a round-trip: encode to prove data is JSON-serializable, decode back to a Lua table.
- **`process.spawn_monitored(entry, host, ...args)`** — arguments passed after the host are forwarded to the process's
  `main(...)` function. Pipeline stages receive `next_pid` this way.
- **End-of-stream signaling** — the `done` topic propagates through all stages, each stage forwards it and exits.
  The aggregator uses it to trigger the final summary.
- **`msg:payload():data()`** — always unwrap payloads. Every stage in the pipeline uses this pattern.
- **`tostring(process.pid())`** — the CLI passes its PID as a string in the `done` message so the aggregator can reply
  back. PID userdata doesn't survive serialization.
