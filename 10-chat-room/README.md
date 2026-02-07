# Chat Room — Everything Combined

A chat system where each room is an isolated process. Combines all major Wippy concepts: processes, messages, events,
app registry, and process registry. A notification service watches all activity via the event bus, rooms register
themselves for discovery, and the CLI orchestrator simulates multi-user chat across two rooms.

## Architecture

```
CLI (orchestrator)
│
├── spawn("general")  ──▶  Room Process "general"
│                           members = {Alice, Bob}
│                           history = [...]
│                           process.registry.register("room:general")
│                           registry entry: app:room.general
│
├── spawn("random")   ──▶  Room Process "random"
│                           members = {Alice, Charlie}
│                           history = [...]
│                           process.registry.register("room:random")
│                           registry entry: app:room.random
│
│   send_to_room("general", "message", {user, text})
│   ────────────────────────────────────▶ │ logs, emits event
│                                         │
│                     Notification Service (auto-started)
│                       events.subscribe("chat")
│                       logs: [NOTIFY] New message in #general by Alice
```

Rooms are spawned dynamically and register themselves in two ways:
1. **Process registry** (`process.registry.register("room:general")`) — for message routing by name
2. **App registry** (`registry.snapshot()` + `changes:create()`) — for discovery via `registry.find()`

## Project Structure

```
10-chat-room/
├── wippy.lock
└── src/
    ├── _index.yaml           # Registry entries
    ├── room.lua              # Room process: members, history, events
    ├── notifications.lua     # Event subscriber: logs all chat activity
    └── cli.lua               # Orchestrator: creates rooms, simulates chat
```

## Registry Entries

| Entry                   | Kind              | Purpose                                  |
|-------------------------|-------------------|------------------------------------------|
| `app:terminal`          | `terminal.host`   | Terminal host (provides stdout)          |
| `app:processes`         | `process.host`    | Worker pool for room processes           |
| `app:room`              | `process.lua`     | Room process (spawned per room)          |
| `app:notifications_process` | `process.lua` | Notification service implementation      |
| `app:notifications`     | `process.service` | Auto-starts the notification service     |
| `app:cli`               | `process.lua`     | CLI orchestrator (entry point)           |

Additionally, each room dynamically creates a `registry.entry` with `meta.type = "chat.room"` at runtime.

## Running

```bash
cd examples/10-chat-room
wippy init
wippy run -x app:cli
```

**Output:**

```
=== Chat Room: Everything Combined ===

Features used:
  - Process per room (actor with isolated state)
  - Messages for join/leave/chat/info
  - Event bus for notifications (loose coupling)
  - Registry for room discovery
  - process.registry for name-based routing

Creating rooms...

Users joining rooms...

Chatting...

Querying room info...
  #general: 2 members (Alice, Bob), 4 messages
  #random: 2 members (Alice, Charlie), 3 messages

Discovering rooms via registry:
  Found: #general (app:room.general)
  Found: #random (app:room.random)

Cleaning up...

Done! Each room was a process, events notified all subscribers,
and registry made rooms discoverable. No shared state anywhere.
```

## Room Messages

| Topic      | Payload             | Effect                                      |
|------------|---------------------|---------------------------------------------|
| `join`     | `{user}`            | Add user to members, emit `user.joined`     |
| `leave`    | `{user}`            | Remove from members, emit `user.left`       |
| `message`  | `{user, text}`      | Add to history, emit `message.sent`         |
| `get_info` | `{reply_to}`        | Reply with members, message count, history  |
| `close`    | `{}`                | Unregister, emit `room.closed`, exit        |

## Event Bus Topics

All events are published on the `"chat"` topic:

| Event Kind       | Path                  | Data                |
|------------------|-----------------------|---------------------|
| `room.created`   | `/rooms/{name}`       | `{room}`            |
| `room.closed`    | `/rooms/{name}`       | `{room}`            |
| `user.joined`    | `/rooms/{name}`       | `{room, user}`      |
| `user.left`      | `/rooms/{name}`       | `{room, user}`      |
| `message.sent`   | `/rooms/{name}`       | `{room, user, text}`|

## Key Concepts

- **Process per room** — each room is a `process.spawn()` with isolated state (members, history). No shared memory
  between rooms.
- **Dual registration** — rooms use `process.registry` for message routing (point-to-point) and app `registry` for
  discovery (query-based).
- **Event bus for loose coupling** — the notification service subscribes to `"chat"` events and logs activity. It knows
  nothing about room processes directly — events flow through the bus.
- **`registry.find({["meta.type"] = "chat.room"})`** — discovers rooms dynamically. Uses the `meta.` prefix to avoid
  linter warnings.
- **`process.spawn("app:room", "app:processes", "general")`** — the room name is passed as an argument to `main()`.
- **`events.send("chat", "message.sent", "/rooms/general", data)`** — publishes events with topic, kind, path, and
  data. Subscribers match on topic.
