# Terminal Apps

Three interactive TUI applications built with `butschster/tui` and `butschster/monitor`.
All use the Elm Architecture app runtime and run in **raw mode** — keys respond instantly, no Enter needed.

## Running

```bash
cd examples/22-terminal-apps
wippy update           # resolve dependencies
wippy run todo         # launch the todo list
wippy run monitor      # launch the system monitor
```

---

## Todo List (`wippy run todo`)

Interactive todo manager using `textinput`, `list`, `tabs`, `help`.

| Key                    | Action                       |
|------------------------|------------------------------|
| `↑`/`↓` or `j`/`k`     | Move cursor up/down          |
| `Enter` or `Space`     | Toggle done/undone           |
| `a` or `i`             | Start typing a new todo      |
| `d` or `x`             | Delete selected item         |
| `←`/`→` or `1`/`2`/`3` | Switch tab (All/Active/Done) |
| `?`                    | Toggle full help             |
| `q`                    | Quit                         |

---

## System Monitor (`wippy run monitor`)

Real-time dashboard with three tabs. Auto-refreshes every second.
Uses `table_view`, `progress`, `spinner`, `tabs`, and the `butschster/monitor` collector.

| Key                    | Action                                |
|------------------------|---------------------------------------|
| `←`/`→` or `1`/`2`/`3` | Switch tab (Overview/Services/Memory) |
| `↑`/`↓` or `j`/`k`     | Navigate service table                |
| `?`                    | Toggle full help                      |
| `q`                    | Quit                                  |

**Overview** — hostname, PID, CPUs, goroutines, memory, registry entry counts.

**Services** — supervised service table with status, kind, detail, retries, uptime.

**Memory** — full-width progress bars for heap/stack plus detailed stats.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  terminal.host (app:terminal)                                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  app:todo — Interactive todo list                      │     │
│  │  Components: textinput, list, tabs, help               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  app:monitor — System monitor dashboard                │     │
│  │  Components: table_view, progress, spinner, tabs       │     │
│  │  Data: butschster/monitor collector                    │     │
│  │  Refresh: app.tick("1s")                               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  app:logs — System log viewer                          │     │
│  │  Components: viewport, help                            │     │
│  │  Data: butschster/monitor collector                    │     │
│  │  Refresh: app.tick("2s")                               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  process.host (app:processes)                                    │
│  ├── app:svc.heartbeat  (process.service)                       │
│  ├── app:svc.metrics    (process.service)                       │
│  └── app:svc.cleanup    (process.service)                       │
│                                                                  │
│  Dependencies: butschster/tui, butschster/monitor                │
└──────────────────────────────────────────────────────────────────┘
```
