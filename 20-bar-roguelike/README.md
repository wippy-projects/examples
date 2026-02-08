# The Rusty Flagon — A Roguelike Bar Conversation

A roguelike conversation game built with Wippy's actor model and LLM integration. Sit at a
fantasy tavern bar, chat with randomly generated NPCs, and watch wandering characters drift
in and out. NPCs talk to each other, react to arrivals and departures, and fill silences
with their own chatter. Browser-based web UI with WebSockets.

## Concept

You walk into **The Rusty Flagon**, a fantasy tavern. Each time you sit down, a randomly
generated character appears next to you — with their own name, race, occupation, personality,
drunkenness level, mood, secret, speech style, and quirks. Permanent regulars (Barkeep Marta,
Lyric the Lute) are always present, and wandering NPCs arrive and depart every 45–120 seconds.

Chat with them, try to uncover their secrets, buy them drinks, or just enjoy the atmosphere.
Messages are routed intelligently — say "Marta, beer please" and the bartender responds; say
"Hello everyone!" and multiple NPCs chime in. NPCs react to each other too — interjections
can spark short back-and-forth exchanges between characters, and if you stay quiet for a while,
they'll start talking among themselves.

Every character is unique — traits are randomly combined from pools giving **~11.6 billion**
unique character combinations, then sent to an LLM which generates a consistent personality.

## Architecture

```
                                        ┌──────────────────┐
Browser ─ GET / ──▶  Jet Templates      │  Agent           │
       ─ WS /ws/chat ──▶  Session  ──▶  │  (process.service)│
                         │         ◀──  │  LLM generation   │
                         │              ├──────────────────┤
                         │         ──▶  │  Router          │
                         │         ◀──  │  (process.service)│
                         │              │  NPC selection    │
                         │              └──────────────────┘
                         │              ┌──────────────────┐
                         │              │  NPC Manager     │
                         │              │  (process.service)│
                         │              │  wanderer spawner │
                         │              └───────┬──────────┘
                         │                      │
                         │                ┌─────▼─────┐
                         └───── reads ──▶ │  Registry  │
                                          │  (NPCs)    │
                                          └────────────┘
```

Four background services coordinate via message passing:

- **Agent** — receives generation requests, calls `llm.generate()`, returns text
- **Router** — receives player text + NPC list, uses `llm.structured_output()` to pick responders
- **NPC Manager** — adds/removes wandering NPCs from the registry on a timer
- **Session** — per-connection WebSocket process handling user I/O, character generation, conversation history, NPC-to-NPC reaction chains, and idle chatter

## Project Structure

```
20-bar-roguelike/
├── .env                     # OPENAI_API_KEY
├── FLOW.md                  # Detailed message flow diagrams (mermaid)
├── wippy.lock
└── src/
    ├── _index.yaml          # All registry entries
    ├── agent.lua            # LLM generation service
    ├── router.lua           # Message routing service
    ├── session.lua          # WebSocket session process
    ├── npc_manager.lua      # Wandering NPC spawner
    ├── lib/
    │   └── prompts.lua      # Shared prompt building library
    ├── handlers/
    │   ├── page.lua         # GET / → render HTML
    │   ├── chat_data.lua    # Template data function
    │   └── ws_connect.lua   # WS upgrade → spawn session
    └── templates/
        ├── layout.jet       # Base HTML layout
        └── chat.jet         # Chat UI (dark theme, sidebar, WS client)
```

## Registry Entries

| Entry                     | Kind               | Purpose                                         |
|---------------------------|--------------------|-------------------------------------------------|
| `app:__dependency.llm`    | `ns.dependency`    | Pulls in `wippy/llm` (LLM generation)           |
| `app:views`               | `ns.dependency`    | Pulls in `wippy/views` (Jet templating)         |
| `app:processes`           | `process.host`     | Process host for services                       |
| `app:gateway`             | `http.service`     | HTTP server on `:8080`                          |
| `app:router_http`         | `http.router`      | HTTP router at `/`                              |
| `app:ws_router`           | `http.router`      | WebSocket router at `/ws` with relay middleware |
| `app:templates`           | `template.set`     | Jet template set                                |
| `app:layout`              | `template.jet`     | HTML layout template                            |
| `app:chat_page`           | `template.jet`     | Chat page template (view.page)                  |
| `app:chat_data`           | `function.lua`     | Template data function                          |
| `app:page`                | `function.lua`     | GET / handler                                   |
| `app:page.endpoint`       | `http.endpoint`    | Routes GET / to page handler                    |
| `app:ws_connect`          | `function.lua`     | WebSocket upgrade handler                       |
| `app:ws_connect.endpoint` | `http.endpoint`    | Routes GET /ws/chat to WS handler               |
| `app:prompts`             | `library.lua`      | Shared prompt building library                  |
| `app:session_process`     | `process.lua`      | WebSocket session process                       |
| `app:file_env`            | `env.storage.file` | File-based env storage (`.env`)                 |
| `app:gpt_4o_mini`         | `registry.entry`   | Model config: gpt-4o-mini                       |
| `app:agent_process`       | `process.lua`      | Agent process definition                        |
| `app:agent`               | `process.service`  | Supervised agent service                        |
| `app:router_process`      | `process.lua`      | Router process definition                       |
| `app:router`              | `process.service`  | Supervised router service                       |
| `app:npc_manager_process` | `process.lua`      | NPC manager process definition                  |
| `app:npc_manager`         | `process.service`  | Supervised NPC manager service                  |
| `app:npc.bartender`       | `registry.entry`   | Barkeep Marta (permanent NPC)                   |
| `app:npc.bard`            | `registry.entry`   | Lyric the Lute (permanent NPC)                  |

## Setup

1. Set your API key in `.env`:
   ```
   OPENAI_API_KEY=sk-...
   ```

2. Install dependencies:
   ```bash
   wippy install
   ```

## Running

Open http://localhost:8080 in a browser:

```bash
wippy run
```

## Commands

| Command            | Action                                      |
|--------------------|---------------------------------------------|
| `/new`             | Meet a new random character                 |
| `/look`            | See who's at the bar and their traits       |
| `/lang <language>` | Set response language (e.g. `/lang French`) |
| `/help`            | Show available commands                     |
| `/quit`            | Leave the tavern                            |

Any other text is sent as dialogue. Messages are routed to the appropriate NPC(s) — by name
match for direct address, or via LLM routing for ambiguous messages.

## Message Routing

Two-tier routing determines who responds:

1. **Local match** (instant, no LLM) — scans for NPC names, roles, and keywords like "beer"
   or "drink" (routed to bartender). Handles most direct-address messages.

2. **LLM router** (fallback) — for ambiguous messages, uses `llm.structured_output()` with
   conversation context to pick 1–3 responders. Handles group addressing, continuations,
   and context-dependent routing.

After the primary response, other NPCs may **interject** based on their individual probability
(10–30%). The main patron (your seat neighbor) has a 25% interjection chance.

## NPC-to-NPC Conversations

NPCs don't just respond to the player — they talk to each other:

- **Reaction chains** — when an NPC speaks, others have a chance to react *to that NPC*,
  addressing them by name. These chain up to 3 levels deep with decaying probability
  (15% base, halved each level: 15% → 7.5% → 3.75%), creating organic bar chatter.

- **Arrival/departure reactions** — when a wandering NPC enters or leaves the tavern,
  other NPCs may comment on it ("Grimjaw! About time you showed up!").

- **Idle chatter** — if the player is quiet for 30 seconds, NPCs may start talking among
  themselves unprompted (40% chance per interval). This keeps the tavern feeling alive
  even when the player is just watching.

## Character Traits

Each randomly generated character combines:

- **20 names** (Grok the Mild, Elara Nightwhisper, Pip Candlewick...)
- **10 races** (human, dwarf, elf, goblin (reformed), undead (friendly)...)
- **20 occupations** (retired adventurer, potion taste-tester, unlicensed dentist...)
- **18 personalities** (paranoid and conspiratorial, theatrically dramatic...)
- **6 drunkenness levels** (sober to barely conscious)
- **12 moods** (celebrating, hiding from someone, looking for trouble...)
- **15 secrets** (hidden treasure, cursed a goat, pocket full of teeth...)
- **10 speech styles** (nautical terms, flowery language, made-up proverbs...)
- **10 quirks** (fidgets with a coin, talks to empty chair...)

## Wandering NPCs

The NPC manager maintains a pool of 6 predefined wanderers who drift in and out:

| Name             | Race     | Personality                          | Interject |
|------------------|----------|--------------------------------------|-----------|
| Grimjaw          | half-orc | intimidating, secretly writes poetry | 15%       |
| Old Barnaby      | human    | drunk, nostalgic retired sailor      | 25%       |
| Whisper          | tiefling | paranoid info broker, always sober   | 15%       |
| Roska Thundermug | dwarf    | boisterous competitive drinker       | 30%       |
| Sister Vale      | human    | calm traveling healer, judgmental    | 20%       |
| Fang             | goblin   | nervous reformed rat-catcher         | 20%       |

They appear as `registry.entry` entries with `meta.type: bar.npc` and are discovered
automatically by the session and router.

## Key Concepts

- **Actor-model concurrency** — four independent processes (agent, router, NPC manager,
  session) coordinate via `process.send()` message passing over a shared inbox with
  topic + sender filtering.

- **Registry as live state** — permanent NPCs are declared in `_index.yaml`; wanderers
  are created/deleted at runtime via `registry.snapshot()` + `changes`. All consumers
  discover NPCs with `registry.find({["meta.type"] = "bar.npc"})`.

- **WebSocket relay middleware** — the `ws_connect` handler spawns a session process and
  sets `X-WS-Relay` header with `target_pid`. The gateway's middleware bridges the
  WebSocket connection to the process inbox.

- **Supervised services** — agent, router, and NPC manager are `process.service` entries
  with `auto_start: true` and restart policies (max 5 attempts, exponential backoff).

- **Shared prompt library** — `lib/prompts.lua` is a `library.lua` entry imported by
  `session.lua`, keeping character generation and prompt building centralized.

- **Template-based web UI** — `wippy/views` renders Jet templates server-side; the chat
  page includes a full WebSocket client with auto-reconnect, NPC sidebar, and dark theme.

- **Recursive reaction chains** — `try_interjections` is depth-aware and recursive: after
  any NPC speaks, others get a decaying chance to react, creating bounded multi-party
  exchanges without infinite loops.

## Wippy Documentation

- Docs: https://home.wj.wippy.ai/
- LLM index: https://home.wj.wippy.ai/llms.txt
- Process module: https://home.wj.wippy.ai/en/lua/runtime/process
- Registry module: https://home.wj.wippy.ai/en/lua/runtime/registry
- Views module: https://home.wj.wippy.ai/en/lua/web/views
