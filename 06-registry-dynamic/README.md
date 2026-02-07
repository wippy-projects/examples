# Dynamic Registry — Query and Mutate Entries at Runtime

Demonstrates the registry as a live, versioned data store. Starts with 3 tool entries declared in YAML (v0), adds tools
one at a time (v1, v2), then deletes one (v3) — showing create, delete, version progression, and that YAML-declared
and runtime-mutated entries are accessed through the same API.

## Architecture

```
Process (app:cli)
│
│  1) registry.snapshot() → v0, find() → 3 tools (from YAML)
│
│  2) changes:create("app:tool.weather")
│     changes:apply() → v1, find() → 4 tools
│
│  3) changes:create("app:tool.search")
│     changes:apply() → v2, find() → 5 tools
│
│  4) changes:delete("app:tool.summarizer")
│     changes:apply() → v3, find() → 4 tools
```

## Project Structure

```
06-registry-dynamic/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: terminal host, 3 tool entries, CLI process
    └── cli.lua         # Query tools, add 2 more at runtime, query again
```

## Registry Entries

| Entry                 | Kind             | Purpose                         |
|-----------------------|------------------|---------------------------------|
| `app:terminal`        | `terminal.host`  | Terminal host (provides stdout) |
| `app:tool.calculator` | `registry.entry` | Static tool (from YAML)         |
| `app:tool.translator` | `registry.entry` | Static tool (from YAML)         |
| `app:tool.summarizer` | `registry.entry` | Static tool (from YAML)         |
| `app:cli`             | `process.lua`    | CLI process with `main()`       |

At runtime, `app:tool.weather` and `app:tool.search` are added; `app:tool.summarizer` is deleted.

## Running

```bash
cd examples/06-registry-dynamic
wippy init
wippy run -x app:cli
```

**Output:**

```
=== Dynamic Registry ===

1) Tools registered in YAML (version v0):

   [app:tool.calculator] Calculator — Performs basic math operations
   [app:tool.summarizer] Summarizer — Summarizes long text
   [app:tool.translator] Translator — Translates text between languages

2) Adding Weather tool...

   Registry version: v1

   [app:tool.calculator] Calculator — Performs basic math operations
   [app:tool.summarizer] Summarizer — Summarizes long text
   [app:tool.translator] Translator — Translates text between languages
   [app:tool.weather] Weather — Gets current weather for a location

3) Adding Web Search tool...

   Registry version: v2

   [app:tool.weather] Weather — Gets current weather for a location
   [app:tool.search] Web Search — Searches the web for information
   [app:tool.calculator] Calculator — Performs basic math operations
   [app:tool.summarizer] Summarizer — Summarizes long text
   [app:tool.translator] Translator — Translates text between languages

4) Removing Summarizer tool...

   Registry version: v3

   [app:tool.translator] Translator — Translates text between languages
   [app:tool.search] Web Search — Searches the web for information
   [app:tool.calculator] Calculator — Performs basic math operations
   [app:tool.weather] Weather — Gets current weather for a location

Registry is the source of truth.
Each changes:apply() bumps the version atomically.
```

## Key Concepts

- **`registry.entry`** — a static data entry in the registry. Declared in `_index.yaml` with `meta` fields for
  queryable metadata. No code, just data.
- **`registry.find(filter)`** — queries entries matching a filter. Entries from YAML and runtime are returned together.
- **`registry.snapshot()` / `changes:create()` / `changes:delete()` / `changes:apply()`** — the transactional mutation
  API. Take a snapshot, build a changeset (creates and/or deletes), apply atomically. Returns the new registry version.
- **Custom metadata** — entries use `meta.type`, `meta.title`, `meta.description` etc. for domain-specific
  categorization. The registry doesn't impose a schema — your code defines the conventions.
- **Registry as source of truth** — in Wippy, the registry is the central store for configuration, data, and entry
  definitions. Both YAML declarations and runtime mutations use the same query API.
