# Wippy Examples

Learn Wippy step by step — from hello world to a registry-driven job scheduler.

## Core Examples

Each example is self-contained. `cd` into the project directory first.

```bash
cd examples/<name>
wippy run -x app:<entry>   # run a specific process
wippy run                   # start all auto-started services
```

| #  | Example                                 | Concepts                                                 | Run command                   |
|----|-----------------------------------------|----------------------------------------------------------|-------------------------------|
| 01 | [hello-world](01-hello-world)           | Process, terminal I/O                                    | `wippy run -x app:hello`      |
| 02 | [func-call](02-func-call)               | `funcs.call()`, functions as compute units               | `wippy run -x app:cli`        |
| 03 | [ping-pong](03-ping-pong)               | `process.service`, `process.registry`, message exchange  | `wippy run`                   |
| 04 | [worker-pool](04-worker-pool)           | Channels, `coroutine.spawn`, fan-out/fan-in              | `wippy run -x app:pool`       |
| 05 | [supervision](05-supervision)           | Let it crash, manual supervisor, restart with backoff    | `wippy run -x app:supervisor` |
| 06 | [registry-dynamic](06-registry-dynamic) | `registry.snapshot()`, `changes:create/delete/apply`     | `wippy run -x app:cli`        |
| 07 | [event-bus](07-event-bus)               | `events.send()`, `events.subscribe()`, pub/sub           | `wippy run`                   |
| 08 | [pipeline](08-pipeline)                 | Process chain, 4-stage data flow, `json.encode/decode`   | `wippy run -x app:cli`        |
| 09 | [key-value](09-key-value)               | Process as server, request/reply, `process.inbox()`      | `wippy run -x app:cli`        |
| 10 | [chat-room](10-chat-room)               | **All combined**: processes, messages, events, registry  | `wippy run -x app:cli`        |
| 11 | [crontab](11-crontab)                   | `time.after()`, timer loops, one process per job         | `wippy run`                   |
| 12 | [crontab-registry](12-crontab-registry) | Registry-driven discovery, `funcs.call()`, dynamic spawn | `wippy run`                   |
| 13 | [echo-service](13-echo-service)         | `spawn_monitored`, coroutines, workers, request/reply    | `wippy run -x app:cli`        |
| 14 | [task-queue](14-task-queue)             | Queue, SQLite, migrations, concurrent workers            | `wippy run`                   |
| 15 | [env-variables](15-env-variables)      | `env.get/set`, storage backends, router chain, defaults  | `wippy run -x app:cli`        |

## HTTP Examples

These start an HTTP server. Run with `wippy run` and test with `curl`.

| Example                              | Concepts                                              | Port  |
|--------------------------------------|-------------------------------------------------------|-------|
| [http-hello-world](http-hello-world) | Minimal HTTP API: server, router, endpoint, function  | :8080 |
| [http-async-task](http-async-task)   | HTTP + `coroutine.spawn` for background work          | :8080 |
| [http-spawn](http-spawn)             | HTTP + `process.spawn` per task                       | :8080 |
| [shop](shop)                         | Full app: cart per user, registry products, event bus | :8080 |

## Learning Path

```
01 hello-world         — "Everything is a process"
       ↓
02 func-call           — "Functions are stateless calls between processes"
       ↓
03 ping-pong           — "Services discover each other via registry"
       ↓
04 worker-pool         — "Channels coordinate coroutines within a process"
       ↓
05 supervision         — "Let it crash. Supervisors restart."
       ↓
06 registry-dynamic    — "Registry is the source of truth. Extend at runtime."
       ↓
07 event-bus           — "Events decouple publishers from subscribers"
       ↓
08 pipeline            — "Chain processes into data pipelines"
       ↓
09 key-value           — "A process IS a server. State + inbox = service."
       ↓
10 chat-room           — "Combine everything into a real system"
       ↓
11 crontab             — "Timer loops: one process per periodic job"
       ↓
12 crontab-registry    — "Registry-driven config: data defines behavior"
       ↓
13 echo-service        — "Spawn a worker per request, monitor lifecycle"
       ↓
14 task-queue          — "Queues + database: async work with persistence"
       ↓
15 env-variables       — "Configure apps: storage chain, defaults, runtime overrides"
```

## Key Patterns by Example

| Pattern                                 | Examples                |
|-----------------------------------------|-------------------------|
| `process.spawn()` / `spawn_monitored()` | 05, 08, 10, 12, 13      |
| `process.service` (auto-start)          | 03, 07, 09, 11, 12, 13  |
| `process.send()` / `inbox()`            | 03, 08, 09, 10, 13      |
| `process.registry`                      | 03, 09, 10, 13          |
| `channel.select` + `time.after()`       | 08, 09, 10, 11, 12, 13  |
| `channel.new()` + `coroutine.spawn()`   | 04, 13, http-async-task |
| `funcs.call()`                          | 02, 12                  |
| `events.send()` / `subscribe()`         | 07, 10                  |
| `registry.find()` / `snapshot()`        | 06, 10, 12              |
| `json.encode()` / `decode()`            | 08, 14                  |
| `queue.publish()` / `queue.consumer`    | 14                      |
| `sql.get()` / `sql.builder`             | 14                      |
| Migrations (`process.service` one-shot) | 14                      |
| `env.get()` / `env.set()` / `env.get_all()` | 15                 |
| `env.storage.router` (chained backends) | 15                      |
