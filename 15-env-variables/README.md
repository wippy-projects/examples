# Environment Variables — Configuring Apps with `env` Module

A CLI process that reads, writes, and lists environment variables using Wippy's layered storage system. Demonstrates
how to configure applications with defaults, `.env` files, OS variables, and runtime overrides.

## Architecture

```
Terminal Host (app:terminal)
└── Process (app:cli)
    ├── env.get("APP_NAME")         →  "Wippy Env Demo" (from config.env)
    ├── env.get("PORT")             →  "8080" (default)
    ├── env.set("LOG_LEVEL", "debug")  →  written to memory storage
    ├── env.set("APP_VERSION", ...)    →  DENIED (read-only)
    ├── env.get_all()               →  list all accessible vars
    └── return 0

Storage Chain (router):
  1. app:mem_env   (memory)   ← writes go here
  2. app:file_env  (file)     ← config.env
  3. app:os_env    (os)       ← system environment
```

The **router storage** chains three backends. When you read a variable, it searches memory first, then the `.env` file,
then the OS environment. Writes always go to the first storage (memory), so overrides are volatile and don't pollute the
`.env` file or OS.

## Project Structure

```
15-env-variables/
├── config.env          # Persistent config file (KEY=VALUE format)
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: storages, variables, process, function
    ├── cli.lua         # main() → demonstrates env.get, env.set, env.get_all
    └── greet.lua       # call(name) → greeting configured by env vars
```

## Registry Entries

| Entry              | Kind                 | Purpose                                  |
|--------------------|----------------------|------------------------------------------|
| `app:terminal`     | `terminal.host`      | Terminal host (provides stdout)          |
| `app:processes`    | `process.host`       | Process host (runs function invocations) |
| `app:os_env`       | `env.storage.os`     | Read-only OS environment variables       |
| `app:mem_env`      | `env.storage.memory` | Volatile runtime overrides               |
| `app:file_env`     | `env.storage.file`   | Persistent `.env` file storage           |
| `app:config`       | `env.storage.router` | Chains: memory → file → OS               |
| `app:app_name`     | `env.variable`       | APP_NAME with default "My Wippy App"     |
| `app:port`         | `env.variable`       | PORT with default "8080"                 |
| `app:log_level`    | `env.variable`       | LOG_LEVEL with default "info"            |
| `app:api_key`      | `env.variable`       | API_KEY — no default, must be configured |
| `app:app_version`  | `env.variable`       | APP_VERSION — read-only, default "1.0.0" |
| `app:secret_token` | `env.variable`       | Private variable (no public name)        |
| `app:cli`          | `process.lua`        | CLI demo process                         |
| `app:greet`        | `function.lua`       | Greeting function configured by env vars |

## Running

```bash
cd examples/15-env-variables
wippy init
wippy run -x app:cli
```

**Expected Output:**

```
=== Environment Variables ===

── Reading Variables ──
APP_NAME    = Wippy Env Demo
PORT        = 8080
LOG_LEVEL   = warn
APP_VERSION = 1.0.0

── Missing Variable (with error handling) ──
API_KEY     = (not set — expected! configure it in config.env)

── Runtime Overrides (memory storage) ──
Setting LOG_LEVEL = debug ...
LOG_LEVEL   = debug

── Read-Only Variable ──
Cannot set APP_VERSION: PERMISSION_DENIED

── All Accessible Variables ──
  APP_NAME = Wippy Env Demo
  PORT = 8080
  LOG_LEVEL = debug
  APP_VERSION = 1.0.0
  GREETING_STYLE = casual

Done! The router chain searched: memory → file → OS
Writes went to memory storage (volatile, lost on restart).
```

### Overriding with OS environment

```bash
# OS env takes lowest priority — only used if not in memory or file
APP_NAME="From Shell" wippy run -x app:cli

# To make OS override file, remove APP_NAME from config.env first
```

## Key Concepts

- **`env.storage.os`** — read-only access to OS environment variables (`$PATH`, `$HOME`, etc.). Cannot be written to.
- **`env.storage.memory`** — volatile in-memory storage. Fast reads/writes, lost on restart. Ideal for runtime
  overrides.
- **`env.storage.file`** — persistent storage using `.env` files (`KEY=VALUE` format with `#` comments). Set
  `auto_create: true` to create the file automatically.
- **`env.variable`** — a named variable reference. Has an optional `default` value and can be `read_only`. Set the
  `variable` field for public access by name; omit it to make the variable private (accessible only by entry ID).
- **`env.get(key)`** — read a variable. Returns `string, error`. Returns `nil` if not found.
- **`env.set(key, value)`** — write a variable. Returns `boolean, error`. Fails with `PERMISSION_DENIED` for read-only
  variables or read-only storages.
- **`env.get_all()`** — list all accessible variables. Be careful not to log secrets!
- **Module declaration** — the `env` module must be listed in the entry's `modules:` array to be available.

## Storage Priority Pattern

```
env.get("LOG_LEVEL")
    │
    ▼
┌─────────────┐   not found   ┌─────────────┐   not found   ┌─────────────┐
│   Memory    │ ────────────▶ │    File     │ ────────────▶ │     OS      │
│ (overrides) │               │ (config.env)│               │ (system env)│
└─────────────┘               └─────────────┘               └─────────────┘
    ▲
    │
env.set("LOG_LEVEL", "debug")   ← writes always go to first storage
```

This pattern lets you:

1. Ship defaults in `_index.yaml` (via `default:` on variables)
2. Override per-environment in `.env` files
3. Override per-session via OS env (`KEY=value wippy run`)
4. Override at runtime via `env.set()` (memory, volatile)
