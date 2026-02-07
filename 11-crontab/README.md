# Crontab — Periodic Job Scheduler

A cron-like scheduler where each job runs as its own isolated process. Four jobs fire at different intervals using
`time.after()` + `channel.select`. Demonstrates that spawning multiple processes is lightweight — each job is a
`process.service` with its own PID, timer loop, and execution counter.

## Architecture

```
wippy run
│
├── app:heartbeat  {0x00006}  ── timer 1s ──▶ TICK ──▶ reset timer ──▶ ...
├── app:cleanup    {0x00004}  ── timer 3s ──▶ TICK ──▶ reset timer ──▶ ...
├── app:report     {0x00003}  ── timer 5s ──▶ TICK ──▶ reset timer ──▶ ...
└── app:backup     {0x00008}  ── timer 7s ──▶ TICK ──▶ reset timer ──▶ ...
```

Each job is a separate process with its own PID. All 4 share a single source file (`jobs.lua`) but use different
`method:` entry points. Processes are cheap — no reason to cram everything into one.

## Project Structure

```
11-crontab/
├── wippy.lock
└── src/
    ├── _index.yaml       # Registry: process host, 4 job processes + 4 services
    └── jobs.lua          # Shared job loop with 4 exported methods
```

## Registry Entries

| Entry                   | Kind              | Purpose                           |
|-------------------------|-------------------|-----------------------------------|
| `app:processes`         | `process.host`    | Worker pool for job processes     |
| `app:heartbeat_process` | `process.lua`     | Heartbeat job (method: heartbeat) |
| `app:heartbeat`         | `process.service` | Auto-starts heartbeat             |
| `app:cleanup_process`   | `process.lua`     | Cleanup job (method: cleanup)     |
| `app:cleanup`           | `process.service` | Auto-starts cleanup               |
| `app:report_process`    | `process.lua`     | Report job (method: report)       |
| `app:report`            | `process.service` | Auto-starts report                |
| `app:backup_process`    | `process.lua`     | Backup job (method: backup)       |
| `app:backup`            | `process.service` | Auto-starts backup                |

## Running

```bash
cd examples/11-crontab
wippy init
wippy run
# Watch logs — 4 processes fire at different intervals
# Ctrl+C to stop (each job logs its run count)
```

**Output (logs):**

```
INFO  Job started       name=heartbeat  interval=1s  pid={app:processes|0x00006}
INFO  Job started       name=cleanup    interval=3s  pid={app:processes|0x00004}
INFO  Job started       name=report     interval=5s  pid={app:processes|0x00003}
INFO  Job started       name=backup     interval=7s  pid={app:processes|0x00008}
INFO  TICK heartbeat    run=1
INFO  TICK heartbeat    run=2
INFO  TICK cleanup      run=1
INFO  TICK heartbeat    run=3
INFO  TICK heartbeat    run=4
INFO  TICK report       run=1
INFO  TICK heartbeat    run=5
INFO  TICK cleanup      run=2
INFO  TICK heartbeat    run=6
INFO  TICK backup       run=1
...
INFO  Job stopped       name=heartbeat  runs=11
INFO  Job stopped       name=report     runs=2
INFO  Job stopped       name=cleanup    runs=3
INFO  Job stopped       name=backup     runs=1
```

## Jobs

| Job         | Interval | Description         |
|-------------|----------|---------------------|
| `heartbeat` | 1s       | System health check |
| `cleanup`   | 3s       | Temp file cleanup   |
| `report`    | 5s       | Usage report        |
| `backup`    | 7s       | Incremental backup  |

## Key Concepts

- **One process per job** — each job runs in its own process with an isolated timer loop. Processes are lightweight in
  Wippy, so there's no reason to multiplex jobs into a single process.
- **Shared source, multiple methods** — all 4 jobs use `source: file://jobs.lua` but reference different `method:` entry
  points (`heartbeat`, `cleanup`, `report`, `backup`). One file, four processes.
- **`time.after(interval)`** — creates a one-shot timer channel. Not periodic — must create a new timer after each
  firing. The pattern is: wait for timer, handle tick, reset timer.
- **`channel.select` with timer + events** — each job selects on its timer and `process.events()`. When the timer fires,
  it ticks. When `CANCEL` arrives (Ctrl+C), it logs final stats and exits.
- **`process.service` with `auto_start`** — all 4 jobs start automatically with `wippy run`. No orchestrator needed.
