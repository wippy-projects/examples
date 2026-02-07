# Conversation Flow — The Rusty Flagon

## Process Architecture

```mermaid
graph LR
    CLI["cli.lua<br/>(terminal)"]
    AGENT["agent.lua<br/>(process.service)"]
    ROUTER["router.lua<br/>(process.service)"]
    NPC_MGR["npc_manager.lua<br/>(process.service)"]
    REG[(Registry)]
    LLM_API[/"OpenAI API<br/>(gpt-4o-mini)"/]

    CLI -->|process.send 'route'<br/>text + context| ROUTER
    ROUTER -->|process.send 'route_result'<br/>targets list| CLI
    CLI -->|process.send 'generate'| AGENT
    AGENT -->|process.send 'result'| CLI
    ROUTER -->|registry.find<br/>loads NPCs| REG
    ROUTER -->|llm.structured_output| LLM_API
    AGENT -->|llm.generate| LLM_API
    NPC_MGR -->|registry.snapshot + changes| REG
    CLI -->|registry.find| REG
```

## Message Flow: Player Types Something

```mermaid
sequenceDiagram
    participant Player
    participant CLI as cli.lua
    participant Router as router.lua
    participant LLM1 as LLM (routing)
    participant Agent as agent.lua
    participant LLM2 as LLM (generation)

    Player->>CLI: types "Hey Marta, beer please"

    Note over CLI: 1. sync_npcs() — detect arrivals/departures

    Note over CLI: 2. Add player message to chat_log

    Note over CLI: 3. local_route() — "Marta" found in "Barkeep Marta"
    Note over CLI: → returns {"app:npc.bartender"} (fast, no LLM)

    Note over CLI: 4. Single target → generate response

    CLI->>Agent: process.send(agent_pid, "generate", {<br/>  system: build_addressed_prompt(marta),<br/>  messages: build_llm_messages(chat_log, "app:npc.bartender")<br/>})

    Agent->>LLM2: llm.generate(...)
    LLM2-->>Agent: "Coming right up, love..."
    Agent->>CLI: process.send(sender, "result", {text: "Coming right up, love..."})

    Note over CLI: 5. Append Marta's response, spoke_ids = {["app:npc.bartender"]=true}

    Note over CLI: 6. try_interjections() — skip Marta, others may chime in
```

## Message Flow: Group Addressing

```mermaid
sequenceDiagram
    participant Player
    participant CLI as cli.lua
    participant Router as router.lua
    participant LLM1 as LLM (routing)
    participant Agent as agent.lua
    participant LLM2 as LLM (generation)

    Player->>CLI: types "Hello everyone! What's the best drink here?"

    Note over CLI: 1. local_route() → nil (no specific name match)

    CLI->>Router: process.send(router_pid, "route", {<br/>  text: "Hello everyone! ...",<br/>  npcs: [{id, name, role, personality, drunk_level}, ...],<br/>  main_npc_id: "main"<br/>})

    Router->>LLM1: llm.structured_output(ROUTE_SCHEMA, prompt, ...)
    Note over LLM1: Schema: {responders: [{target_id, reason}]}<br/>Picks 2-3 NPCs who'd naturally respond

    LLM1-->>Router: {responders: [<br/>  {target_id: "app:npc.bartender", reason: "bartender duty"},<br/>  {target_id: "main", reason: "sitting next to player"},<br/>  {target_id: "app:wanderer.roska", reason: "drunk, opinionated about drinks"}<br/>]}

    Router->>CLI: route_result {targets: ["app:npc.bartender", "main", "app:wanderer.roska"]}

    Note over CLI: 2. Iterate targets in order

    loop For each target (Marta, Main, Roska)
        CLI->>Agent: generate with target's prompt + chat_log
        Agent->>LLM2: llm.generate(...)
        LLM2-->>Agent: response
        Agent->>CLI: result
        Note over CLI: Append response, add to spoke_ids
    end

    Note over CLI: 3. try_interjections() — skip spoke_ids<br/>(Marta, Main, Roska already spoke)
```

## Failure Scenario: Router Fails → Main NPC Responds

```mermaid
sequenceDiagram
    participant CLI as cli.lua
    participant Router as router.lua
    participant Agent as agent.lua

    Note over CLI: local_route() → nil (no name match)

    CLI->>Router: process.send("route", {text: "What a night!"})
    Note over CLI: ⏳ waiting on inbox (15s timeout)

    alt Router crashes
        Note over Router: ❌ Process dies, restarts
        Note over CLI: ⏳ ...15 seconds pass...
        Note over CLI: Timeout! ask_router returns {"main"}
    else Router returns error
        Router->>CLI: route_result {targets: {"main"}}
    else Router lookup fails
        Note over CLI: process.registry.lookup("router") = nil<br/>ask_router returns {"main"} immediately
    end

    Note over CLI: targets = {"main"}<br/>→ main NPC responds

    CLI->>Agent: generate with main NPC's system_prompt
    Agent->>CLI: main NPC response
```

## Key Concern: Shared Inbox — FIXED

The CLI process uses a single inbox for communication with both the router and the agent.
Both `ask_router()` and `ask_agent()` now **loop with topic + sender filtering**, discarding
stale messages from the wrong service.

```mermaid
sequenceDiagram
    participant CLI as cli.lua (single inbox)
    participant Router as router.lua
    participant Agent as agent.lua

    CLI->>Router: "route" message
    Note over CLI: ⏳ waiting for topic="route_result" from=router_pid

    Note right of CLI: ✅ Stale "result" from agent<br/>is discarded with a warning.<br/>Loop continues waiting for<br/>the correct "route_result".

    Router->>CLI: "route_result" {target_id: ...}
    Note over CLI: ✅ topic matches, sender matches → accept
```

### Additional fixes applied:
- **System messages prefixed with `[Narrator]:`** — `build_llm_messages` now marks
  arrival/departure events distinctly so the LLM doesn't confuse narration with player speech.
- **Main patron can interject** — When a registry NPC is directly addressed, the main patron
  (the person you're sitting next to) now has a 25% chance to chime in, making conversations
  feel more natural.
- **Sender validation** — Both `ask_agent` and `ask_router` verify `msg:from()` matches
  the expected service PID, not just the topic.

## NPC Manager (background, independent)

```mermaid
sequenceDiagram
    participant Timer
    participant NPC_Mgr as npc_manager.lua
    participant Registry

    loop Every 45–120 seconds
        Timer->>NPC_Mgr: timer fires
        alt Add wanderer
            NPC_Mgr->>Registry: snapshot → changes:create({<br/>  id: "app:wanderer.grimjaw",<br/>  kind: "registry.entry",<br/>  meta: {type: "bar.npc", ...},<br/>  data: {entrance: "...", exit: "...", ...}<br/>}) → apply()
        else Remove wanderer
            NPC_Mgr->>Registry: snapshot → changes:delete("app:wanderer.grimjaw") → apply()
        end
    end

    Note over NPC_Mgr: On CANCEL event: cleanup_all() removes<br/>all active wanderers from registry
```

## Diagnosis: Router Issues — Status

| # | Issue | Status | Notes |
|---|---|---|---|
| 1 | `llm.structured_output` panics (wrong args?) | ⚠️ Mitigated | Local name-match in CLI bypasses the LLM router for obvious cases. Router crash only affects ambiguous messages. |
| 2 | `llm.structured_output` doesn't exist in runtime | ⚠️ Mitigated | Same — local routing handles most cases without needing the router process at all. |
| 3 | Shared inbox picks up stale message | ✅ Fixed | `ask_router` and `ask_agent` now loop, filtering by topic AND sender PID. |
| 4 | Router not registered when CLI starts | ✅ Fixed | Local name-match runs first, no dependency on router process. LLM fallback logs a warning if router isn't found. |
| 5 | Structured output returns name instead of ID | ✅ Fixed | Router now does fuzzy matching — if LLM returns "Marta", "Barkeep Marta", "bartender", or "npc.bartender", it resolves to `app:npc.bartender`. |
| 6 | Strict ID validation silently drops correct results | ✅ Fixed | Was the root cause. Router validation was exact-match only (`answer == npc.id`). LLM routinely returned names/roles instead of full qualified IDs like `app:npc.bartender`, causing every message to default to main patron. |
| 7 | System messages confuse LLM responses | ✅ Fixed | Arrival/departure narration now prefixed with `[Narrator]:` in `build_llm_messages`. |
| 8 | Main patron can't interject when others speak | ✅ Fixed | `try_interjections` now gives the main patron a 25% chance to chime in when a registry NPC is directly addressed. |

### Routing Architecture

```
Player says "Marta, beer please!"
│
├─► local_route() — name match: "Marta" ∈ "Barkeep Marta"
│   Returns: {"app:npc.bartender"} (instant, no LLM)
│
└─► (skipped)

Player says "Beer please" (no name)
│
├─► local_route() — ORDER_KEYWORDS: "beer" → find_bartender()
│   Returns: {"app:npc.bartender"} (instant, no LLM)
│
└─► (skipped)

Player says "berer please" (typo, no keyword match)
│
├─► local_route() — no match → nil
│
└─► LLM router (reads NPCs from registry, sees conversation context)
    Context: [Barkeep Marta]: "how about I pour you a small one?"
    → LLM infers continuation → {"app:npc.bartender"}

Player says "Hello everyone!"
│
├─► local_route() — no match → nil
│
└─► LLM router (multi-target)
    → {"app:npc.bartender", "main", "app:wanderer.roska"}
    → Each responds in order, then interjections from the rest

Player says "yes" / "tell me more" (continuation)
│
├─► local_route() — no match → nil
│
└─► LLM router sees recent context → routes to whoever was just talking
```

## Remaining Design Concerns

| # | Concern | Impact | Suggested Fix |
|---|---|---|---|
| 1 | **Unbounded chat_log** | LLM context window overflow on long conversations; ever-growing render time | Add a sliding window (e.g. keep last 30 messages for LLM, full log for display) |
| 2 | **No CANCEL handling in CLI** | Process can't shut down gracefully; must be force-killed | Add `process.events()` monitoring in the input loop (requires non-blocking input or a select with events channel) |
| 3 | **ID style mismatch** | Main patron uses bare `"main"` while registry NPCs use `"app:npc.bartender"` format. The LLM might not treat `"main"` as a proper ID | Use a more distinctive ID like `"patron_main"` or `"player_companion"` |
| 4 | **Sequential interjections** | Multiple interjecting NPCs cause sequential LLM calls, each blocking 2-10s | Accept for now; parallel calls would require managing multiple outstanding agent requests |
| 5 | **Startup timing fragility** | 1s sleep before first registry load may miss slow-starting services | Use retry loop with backoff for initial `process.registry.lookup` calls |
