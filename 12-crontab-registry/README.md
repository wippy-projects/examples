# Crontab Registry — Data-Driven Job Scheduler

A registry-driven cron scheduler. Jobs are `function.lua` entries with `meta.type: cron.job` — each is both callable
via `funcs.call()` and discoverable via `registry.find()`. A scheduler process discovers them at startup and spawns a
generic worker for each. The worker calls the job function on a timer. Adding a new job = adding a `function.lua` entry.

## Architecture

```
_index.yaml                              Scheduler (service)
┌─────────────────────────────┐          │
│ job.heartbeat  function 1s  │          │  registry.find({["meta.type"] = "cron.job"})
│ job.cleanup    function 3s  │ discover │  → 4 job functions found
│ job.report     function 5s  │────────▶ │
│ job.backup     function 7s  │          │  spawn worker for each:
└─────────────────────────────┘          ├── Worker {0x00005} → funcs.call("app:job.heartbeat") every 1s
                                         ├── Worker {0x00006} → funcs.call("app:job.cleanup")   every 3s
                                         ├── Worker {0x00003} → funcs.call("app:job.report")    every 5s
                                         └── Worker {0x00004} → funcs.call("app:job.backup")    every 7s
```

The scheduler discovers and spawns. Each worker runs a timer loop and calls its assigned function via `funcs.call()`.
The function returns a result that gets logged.

## Project Structure

```
12-crontab-registry/
├── wippy.lock
└── src/
    ├── _index.yaml       # process host, scheduler, worker, 4 job functions
    ├── scheduler.lua     # Discovers job functions, spawns workers
    ├── worker.lua        # Generic worker: main(entry_id, interval)
    └── jobs.lua          # Job functions: heartbeat, cleanup, report, backup
```

## Registry Entries

| Entry                   | Kind              | Purpose                          |
|-------------------------|-------------------|----------------------------------|
| `app:processes`         | `process.host`    | Worker pool                      |
| `app:scheduler_process` | `process.lua`     | Scheduler implementation         |
| `app:scheduler`         | `process.service` | Auto-starts the scheduler        |
| `app:worker`            | `process.lua`     | Generic worker (spawned per job) |
| `app:job.heartbeat`     | `function.lua`    | Job function: heartbeat, 1s      |
| `app:job.cleanup`       | `function.lua`    | Job function: cleanup, 3s        |
| `app:job.report`        | `function.lua`    | Job function: report, 5s         |
| `app:job.backup`        | `function.lua`    | Job function: backup, 7s         |

### Job Function Schema

```yaml
- name: job.example
  kind: function.lua
  source: file://jobs.lua
  method: example
  meta:
    type: cron.job          # discoverable by scheduler
    interval: "10s"         # how often to call the function
```

To add a new job: write a function in `jobs.lua`, add a `function.lua` entry with `meta.type: cron.job`. The scheduler
discovers and runs it automatically.

## Running

```bash
cd examples/12-crontab-registry
wippy init
wippy run
# Watch logs — scheduler discovers jobs, spawns workers, functions return results
# Ctrl+C to stop
```

**Output (logs):**

```
INFO  Scheduler started     pid={app:processes|0x00002}
INFO  Discovered jobs       count=4
INFO  Spawning worker       entry=app:job.heartbeat  interval=1s
INFO  Spawning worker       entry=app:job.cleanup    interval=3s
INFO  Spawning worker       entry=app:job.report     interval=5s
INFO  Spawning worker       entry=app:job.backup     interval=7s
INFO  Worker started        entry=app:job.heartbeat  interval=1s  pid={0x00005}
INFO  Worker started        entry=app:job.cleanup    interval=3s  pid={0x00006}
INFO  Worker started        entry=app:job.report     interval=5s  pid={0x00003}
INFO  Worker started        entry=app:job.backup     interval=7s  pid={0x00004}
INFO  TICK                  entry=app:job.heartbeat  run=1  result=ok
INFO  TICK                  entry=app:job.heartbeat  run=2  result=ok
INFO  TICK                  entry=app:job.cleanup    run=1  result=7 files removed
INFO  TICK                  entry=app:job.heartbeat  run=3  result=ok
INFO  TICK                  entry=app:job.report     run=1  result=cpu=92% mem=51%
INFO  TICK                  entry=app:job.backup     run=1  result=355KB written
...
INFO  Worker stopped        entry=app:job.heartbeat  runs=11
INFO  Worker stopped        entry=app:job.report     runs=2
INFO  Worker stopped        entry=app:job.cleanup    runs=3
INFO  Worker stopped        entry=app:job.backup     runs=1
INFO  Scheduler stopping
```

## Comparison with Example 11

| Aspect       | 11-crontab                        | 12-crontab-registry                    |
|--------------|-----------------------------------|----------------------------------------|
| Job config   | Hardcoded process.lua + service   | `function.lua` with `meta.type`        |
| Job logic    | Inline in timer loop              | Separate functions called via `funcs`  |
| Discovery    | Static (4 service entries)        | Dynamic (`registry.find()`)            |
| Adding a job | New process.lua + service entries | New function + `function.lua` entry    |
| Processes    | 4 services, each auto-started     | 1 scheduler spawns workers dynamically |
| Execution    | Direct timer loop                 | `funcs.call(entry_id)` per tick        |

## Key Concepts

- **`function.lua` as job definition** — each job is a callable function with metadata. The same entry serves two
  purposes: `meta.type: cron.job` makes it discoverable, `funcs.call(entry_id)` makes it executable.
- **`registry.find({["meta.type"] = "cron.job"})`** — discovers all job functions. New entries are found automatically.
- **`funcs.call(entry_id)`** — calls a registered function by its entry ID. The worker doesn't know what the function
  does — it just calls it and logs the result.
- **`process.spawn("app:worker", "app:processes", entry_id, interval)`** — the scheduler passes the entry ID and
  interval as spawn arguments. The worker uses them to set up its timer and target function.
- **Separation of concerns** — YAML declares *what* and *when*. `jobs.lua` implements *how*. `worker.lua` handles
  *scheduling*. `scheduler.lua` handles *discovery*. Each file has a single responsibility.
