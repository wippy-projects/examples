# Event Bus — Publish / Subscribe

Three auto-started services: a **publisher** emits user lifecycle events, an **audit log** logs every event, and a
**counter** tracks totals by event kind. All communicate through the event bus — the publisher doesn't know who listens.

## Architecture

```
Process Host (app:processes)
├── Publisher (service)                  Event Bus ("users" topic)
│   events.send("users", kind, ...)     │
│ ─────────────────────────────────────▶│
│                                       ├──▶ Audit Log (service)
│   ...8 events, then exit...           │    logs every event
│                                       ├──▶ Counter (service)
│                                       │    counts by event kind
```

All three are `process.service` entries that auto-start with `wippy run`. Subscribers subscribe to the `"users"` topic
and independently process every event.

## Project Structure

```
07-event-bus/
├── wippy.lock
└── src/
    ├── _index.yaml     # Registry: process host, 3 services
    ├── publisher.lua   # Emits 8 user events to the "users" topic
    ├── audit_log.lua   # Subscriber: logs every event
    └── counter.lua     # Subscriber: counts events by kind
```

## Registry Entries

| Entry                    | Kind              | Purpose                            |
|--------------------------|-------------------|------------------------------------|
| `app:processes`          | `process.host`    | Worker pool for all services       |
| `app:audit_log`          | `process.lua`     | Audit log process definition       |
| `app:audit_log.service`  | `process.service` | Supervised audit log (auto-start)  |
| `app:counter`            | `process.lua`     | Counter process definition         |
| `app:counter.service`    | `process.service` | Supervised counter (auto-start)    |
| `app:publisher`          | `process.lua`     | Publisher process definition       |
| `app:publisher.service`  | `process.service` | Supervised publisher (auto-start)  |

## Running

```bash
cd examples/07-event-bus
wippy init
wippy run
```

Ctrl+C to stop after the publisher finishes.

**Logs (3 processes interleaved):**

```
INFO  Publisher started, emitting user events...       {pid: 0x00002}
INFO  Publishing                {kind: "user.created", path: "/users/1"}
INFO  [AUDIT] user.created      {path: "/users/1", data: {name: "Alice"}}
INFO  [COUNTER] Running totals  {user.created: 1}
INFO  Publishing                {kind: "user.created", path: "/users/2"}
INFO  [AUDIT] user.created      {path: "/users/2", data: {name: "Bob"}}
INFO  [COUNTER] Running totals  {user.created: 2}
INFO  Publishing                {kind: "user.login", path: "/users/1"}
INFO  [AUDIT] user.login        {path: "/users/1", data: {name: "Alice"}}
INFO  [COUNTER] Running totals  {user.created: 2, user.login: 1}
...
INFO  [COUNTER] Running totals  {user.created: 3, user.deleted: 1, user.login: 3, user.updated: 1}
INFO  All events published. Publisher doesn't know who listens.
```

## Key Concepts

- **`events.send(topic, kind, path, data)`** — publishes an event to a topic. All subscribers on that topic receive it.
  The publisher doesn't know or care who listens.
- **`events.subscribe(topic)`** — subscribes to all events on a topic. Returns a subscription with a `:channel()` for
  use in `channel.select`.
- **`evt.kind` / `evt.path` / `evt.data`** — event fields use dot notation (not method calls). This differs from
  process messages which use `msg:topic()` and `msg:payload():data()`.
- **`process.event.CANCEL`** — received via `process.events()` when the runtime is shutting down. Subscribers use this
  to clean up (`sub:close()`) and exit gracefully.
- **Pub/sub vs point-to-point** — events are broadcast to all subscribers (1-to-many). Process messages via
  `process.send()` are point-to-point (1-to-1). Use events for loose coupling; use messages for direct communication.
