# Function Calls — Calling Registered Functions with `funcs.call()`

A CLI process that calls two registered functions (`double` and `greet`) via `funcs.call()`. Demonstrates how processes
invoke stateless functions by registry name.

## Architecture

```
Terminal Host (app:terminal)
└── Process (app:cli)
    ├── funcs.call("app:double", 21)  →  42
    ├── funcs.call("app:greet", "Alice")  →  "Hello, Alice! ..."
    ├── funcs.call("app:double", 1..5)  →  loop
    └── return 0

Registry:
  app:double  (function.lua)  →  n * 2
  app:greet   (function.lua)  →  "Hello, " .. name
```

A `process.lua` uses the `funcs` module to call `function.lua` entries by their registry ID. Functions are stateless —
call, get result, done.

## Project Structure

```
02-func-call/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: terminal host, process host, functions, CLI process
    ├── cli.lua         # main() → calls double and greet via funcs.call()
    ├── double.lua      # call(n) → n * 2
    └── greet.lua       # call(name) → greeting string
```

## Registry Entries

| Entry           | Kind            | Purpose                                   |
|-----------------|-----------------|-------------------------------------------|
| `app:terminal`  | `terminal.host` | Terminal host (provides stdout)           |
| `app:processes` | `process.host`  | Process host (runs function invocations)  |
| `app:double`    | `function.lua`  | Doubles a number                          |
| `app:greet`     | `function.lua`  | Greets a person by name                   |
| `app:cli`       | `process.lua`   | CLI entry point that calls both functions |

## Running

```bash
cd examples/02-func-call
wippy run -x app:cli
```

**Output:**

```
=== Function Calls ===

double(21) = 42
greet('Alice') = Hello, Alice! Welcome to Wippy.

Calling double() in a loop:
  double(1) = 2
  double(2) = 4
  double(3) = 6
  double(4) = 8
  double(5) = 10

Functions are stateless. Each call is independent.
```

## Key Concepts

- **`function.lua`** — a stateless callable entry. Defines a `call()` method that takes arguments and returns a result.
  No persistent state between invocations.
- **`funcs.call(id, ...args)`** — invokes a registered function by its entry ID (e.g., `"app:double"`). Returns
  `result, err` — always check for errors.
- **Process vs Function** — a `process.lua` has a `main()` that runs continuously with its own memory. A `function.lua`
  has a `call()` that runs once per invocation. Processes call functions, not the other way around.
- **`process.host`** — required for running function invocations. The process host manages the worker pool that executes
  `funcs.call()` requests.
