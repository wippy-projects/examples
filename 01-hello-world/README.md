# Hello World — The Simplest Wippy Process

A minimal example that runs a single process on a terminal host. The process prints to stdout and exits — demonstrating
that **everything in Wippy runs inside a process**.

## Architecture

```
Terminal Host (app:terminal)
└── Process (app:hello)
    ├── io.print("Hello from Wippy!")
    ├── io.print(process.pid())
    └── return 0  →  process exits
```

A `terminal.host` provides stdin/stdout access. The `process.lua` entry defines the code to run. The `-x` flag launches
the process and exits when it returns.

## Project Structure

```
01-hello-world/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: terminal host + hello process
    └── hello.lua       # main() → print messages → return 0
```

## Registry Entries

| Entry          | Kind            | Purpose                           |
|----------------|-----------------|-----------------------------------|
| `app:terminal` | `terminal.host` | Terminal host (provides stdout)   |
| `app:hello`    | `process.lua`   | Hello world process with `main()` |

## Running

```bash
cd examples/01-hello-world
wippy run -x app:hello
```

**Output:**

```
Hello from Wippy!
My PID: {app:terminal|0x00001}

This is a process — the basic unit of computation.
Every piece of code in Wippy runs inside a process.
Each process has its own isolated memory.
```

### `wippy run -x` vs `wippy run`

| Command                  | Behavior                                                                    |
|--------------------------|-----------------------------------------------------------------------------|
| `wippy run -x app:hello` | Runs the specified process, auto-detects the terminal host, exits when done |
| `wippy run`              | Starts the full runtime and keeps it alive (for servers, long-running apps) |

Use `-x` for CLI-style programs that run and exit. Use bare `wippy run` for HTTP servers and services that should stay
alive (see `http-async-task/`, `shop/` examples).

## Key Concepts

- **Process** (`process.lua`) — the basic unit of computation. Every piece of code runs inside one. Each process has
  isolated memory and a unique PID.
- **Terminal host** (`terminal.host`) — a host that bridges a process to stdin/stdout. Required for CLI-style programs.
  For advanced configuration, see the `wippy/terminal` module.
- **Modules** — built-in capabilities granted to a process. This example uses `io` for `io.print()`.
- **`return 0`** — a process returns an exit code. `0` means success; the process terminates and its memory is freed.
