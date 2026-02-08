local json = require("json")
local logger = require("logger")
local time = require("time")
local registry = require("registry")
local events = require("events")
local prompts = require("prompts")

-- ════════════════════════════════════════════════════════════
-- Constants
-- ════════════════════════════════════════════════════════════

local MAX_LLM_MESSAGES = 30
local MAIN_INTERJECTION_CHANCE = 0.25
local IDLE_TIMEOUT = "600s"
local MAX_NPC_CHAIN_DEPTH = 3
local NPC_REACTION_CHANCE = 0.15
local NPC_REACTION_DECAY = 0.5
local IDLE_CHATTER_DELAY = "30s"
local IDLE_CHATTER_CHANCE = 0.4
local FAREWELL_CHANCE = 0.7

local NPC_COLORS = {
    "#c882ff", "#ff82b4", "#64dcc8", "#ffa064",
    "#b4dc64", "#82b4ff", "#ffc896",
}
local BARKEEP_COLOR = "#ffb450"
local MAIN_NPC_COLOR = "#78c8ff"

local ORDER_KEYWORDS = {
    "beer", "ale", "drink", "whiskey", "whisky", "wine", "mead",
    "round", "grog", "pour", "refill", "brew", "pint", "tankard",
    "shot", "rum", "vodka", "cocktail", "tab", "menu",
    "another one", "same again", "one more",
}

-- ════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════

local function send_to_client(state, message)
    if not state.client_pid then
        logger:warn("send_to_client: no client_pid")
        return
    end
    logger:info("sending to client", { msg_type = message.type, client_pid = state.client_pid })
    process.send(state.client_pid, "ws.send", {
        type = "text",
        data = json.encode(message),
    })
end

local function get_npc_color(state, npc_id, role)
    if state.npc_color_map[npc_id] then
        return state.npc_color_map[npc_id]
    end
    local color
    if role == "bartender" then
        color = BARKEEP_COLOR
    else
        state.npc_color_idx = state.npc_color_idx + 1
        color = NPC_COLORS[((state.npc_color_idx - 1) % #NPC_COLORS) + 1]
    end
    state.npc_color_map[npc_id] = color
    return color
end

--- Sliding window: only send last N messages to LLM
local function get_llm_window(chat_log)
    local start = math.max(1, #chat_log - MAX_LLM_MESSAGES + 1)
    local window = {}
    for i = start, #chat_log do
        table.insert(window, chat_log[i])
    end
    return window
end

-- ════════════════════════════════════════════════════════════
-- Registry NPC loading & sync
-- ════════════════════════════════════════════════════════════

local function load_registry_npcs(state)
    local entries, err = registry.find({ kind = "registry.entry" })
    if err then return {} end

    local npcs = {}
    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "bar.npc" then
            local role = entry.meta.role or "regular"
            local chance = 0.2
            if entry.data and entry.data.interjection_chance then
                chance = tonumber(entry.data.interjection_chance) or 0.2
            end
            table.insert(npcs, {
                id = entry.id,
                name = entry.meta.name or "Unknown",
                role = role,
                color = get_npc_color(state, entry.id, role),
                interjection_chance = chance,
                data = entry.data or {},
            })
        end
    end
    return npcs
end

local function diff_npcs(old_npcs, new_npcs)
    local old_ids = {}
    for _, npc in ipairs(old_npcs) do old_ids[npc.id] = npc end
    local new_ids = {}
    for _, npc in ipairs(new_npcs) do new_ids[npc.id] = npc end

    local arrivals = {}
    for _, npc in ipairs(new_npcs) do
        if not old_ids[npc.id] then table.insert(arrivals, npc) end
    end
    local departures = {}
    for _, npc in ipairs(old_npcs) do
        if not new_ids[npc.id] then table.insert(departures, npc) end
    end
    return arrivals, departures
end

local function send_npc_list(state)
    local npc_info = {}
    for _, npc in ipairs(state.registry_npcs) do
        table.insert(npc_info, {
            id = npc.id,
            name = npc.name,
            role = npc.role,
            color = npc.color,
            race = npc.data.race or "",
            occupation = npc.data.occupation or "",
            drunk_level = npc.data.drunk_level or "",
            mood = npc.data.mood or "",
        })
    end
    send_to_client(state, {
        type = "character_info",
        character = state.character,
        npcs = npc_info,
    })
end

local function sync_npcs(state)
    local fresh = load_registry_npcs(state)
    local arrivals, departures = diff_npcs(state.registry_npcs, fresh)

    for _, npc in ipairs(arrivals) do
        local entrance = npc.data.entrance
        if not entrance then
            entrance = "*" .. npc.name .. " walks into the tavern.*"
        end
        table.insert(state.chat_log, {
            speaker = "\226\151\134",
            kind = "system",
            npc_id = nil,
            content = entrance,
        })
        send_to_client(state, { type = "system", content = entrance })
    end

    for _, npc in ipairs(departures) do
        local exit_msg = npc.data.exit
        if not exit_msg then
            exit_msg = "*" .. npc.name .. " finishes their drink and heads for the door.*"
        end
        table.insert(state.chat_log, {
            speaker = "\226\151\134",
            kind = "system",
            npc_id = nil,
            content = exit_msg,
        })
        send_to_client(state, { type = "system", content = exit_msg })
    end

    state.registry_npcs = fresh

    if #arrivals > 0 or #departures > 0 then
        send_npc_list(state)
    end

    return #arrivals > 0 or #departures > 0, departures
end

-- ════════════════════════════════════════════════════════════
-- Agent & Router communication
-- ════════════════════════════════════════════════════════════

local function ask_agent(system_prompt, messages)
    local inbox = process.inbox()
    local timeout = time.after("60s")

    local agent_pid = process.registry.lookup("agent")
    if not agent_pid then
        return nil, "agent not found"
    end

    logger:info("sending to agent", { agent_pid = tostring(agent_pid) })
    process.send(agent_pid, "generate", {
        system = system_prompt,
        messages = messages,
    })

    local agent_pid_str = tostring(agent_pid)

    while true do
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == timeout then
            return nil, "timeout waiting for agent"
        end

        local msg = r.value
        local topic = msg:topic()
        local from_str = tostring(msg:from())
        logger:info("ask_agent got message", { topic = topic, from = from_str, expected = agent_pid_str })
        if topic == "result" and from_str == agent_pid_str then
            local data = msg:payload():data()
            if data.error then
                return nil, tostring(data.error)
            end
            return tostring(data.text), nil
        end
    end
end

local function ask_agent_safe(state, system_prompt, messages)
    local text, err = ask_agent(system_prompt, messages)
    if err then
        logger:warn("agent error", { error = err })
        send_to_client(state, {
            type = "error",
            message = "The tavern grows quiet for a moment... (LLM error, try again)",
        })
        return nil
    end
    return text
end

local function find_npc_by_id(registry_npcs, target_id)
    for _, npc in ipairs(registry_npcs) do
        if npc.id == target_id then return npc end
    end
    return nil
end

local function find_bartender(registry_npcs)
    for _, npc in ipairs(registry_npcs) do
        if npc.role == "bartender" or npc.role == "barkeep" then
            return npc.id
        end
    end
    return nil
end

local function local_route(text, registry_npcs)
    local lower = text:lower()
    local best_match = nil
    local best_pos = nil
    local address_window = 40

    for _, npc in ipairs(registry_npcs) do
        local name = npc.name or ""
        for word in name:gmatch("%S+") do
            if #word >= 3 then
                local pos = lower:find(word:lower(), 1, true)
                if pos and pos <= address_window and (not best_pos or pos < best_pos) then
                    best_match = npc.id
                    best_pos = pos
                end
            end
        end
        local pos = lower:find(name:lower(), 1, true)
        if pos and (not best_pos or pos < best_pos) then
            best_match = npc.id
            best_pos = pos
        end
        local role = npc.role or ""
        if role == "bartender" or role == "barkeep" or role == "bard" or role == "healer" then
            pos = lower:find(role:lower(), 1, true)
            if pos and pos <= address_window and (not best_pos or pos < best_pos) then
                best_match = npc.id
                best_pos = pos
            end
        end
    end

    if best_match then return best_match end

    local bartender_id = find_bartender(registry_npcs)
    if bartender_id then
        for _, keyword in ipairs(ORDER_KEYWORDS) do
            if lower:find(keyword, 1, true) then
                return bartender_id
            end
        end
    end

    return nil
end

local function build_route_context(chat_log, max_entries)
    max_entries = max_entries or 6
    local total = #chat_log
    local start = math.max(1, total - max_entries + 1)
    local lines = {}
    for i = start, total do
        local entry = chat_log[i]
        if entry.kind == "system" then
            table.insert(lines, "[Narrator]: " .. entry.content)
        else
            table.insert(lines, "[" .. entry.speaker .. "]: " .. entry.content)
        end
    end
    return table.concat(lines, "\n")
end

local function ask_router(state, text)
    local local_match = local_route(text, state.registry_npcs)
    if local_match then
        return { local_match }
    end

    local router_pid = process.registry.lookup("router")
    if not router_pid then
        return { "main" }
    end

    local context = build_route_context(state.chat_log)

    local inbox = process.inbox()
    local timeout = time.after("15s")

    process.send(router_pid, "route", {
        text = text,
        main_npc_id = "main",
        main_name = state.character.name,
        context = context,
    })

    local router_pid_str = tostring(router_pid)

    while true do
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == timeout then
            logger:warn("router timeout, defaulting to main")
            return { "main" }
        end

        local msg = r.value
        if msg:topic() == "route_result" and tostring(msg:from()) == router_pid_str then
            local data = msg:payload():data()
            if data.targets and type(data.targets) == "table" and #data.targets > 0 then
                return data.targets
            end
            return { data.target_id or "main" }
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- Interjection logic
-- ════════════════════════════════════════════════════════════

local function try_interjections(state, spoke_ids, depth)
    depth = depth or 0
    spoke_ids = spoke_ids or {}

    if depth >= MAX_NPC_CHAIN_DEPTH then
        return
    end

    local chance_multiplier = NPC_REACTION_DECAY ^ depth
    local new_speakers = {}

    -- Registry NPCs
    for _, npc in ipairs(state.registry_npcs) do
        if not spoke_ids[npc.id] then
            local chance
            if depth == 0 then
                chance = npc.interjection_chance
            else
                chance = NPC_REACTION_CHANCE * chance_multiplier
            end

            if math.random() < chance then
                -- Find last NPC speaker (for reaction targeting)
                local last_npc_entry = nil
                if depth > 0 then
                    for i = #state.chat_log, 1, -1 do
                        if state.chat_log[i].kind == "npc" and state.chat_log[i].npc_id ~= npc.id then
                            last_npc_entry = state.chat_log[i]
                            break
                        end
                    end
                end

                local prompt
                if depth > 0 and last_npc_entry then
                    prompt = prompts.build_npc_reaction_prompt(npc, last_npc_entry.speaker, state.language)
                    send_to_client(state, { type = "status", text = npc.name .. " turns to " .. last_npc_entry.speaker .. "..." })
                else
                    prompt = prompts.build_interjection_prompt(npc, state.language)
                    send_to_client(state, { type = "status", text = npc.name .. " chimes in..." })
                end

                local msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), npc.id)
                local response = ask_agent_safe(state, prompt, msgs)

                if response then
                    table.insert(state.chat_log, {
                        speaker = npc.name,
                        kind = "npc",
                        npc_id = npc.id,
                        content = response,
                    })
                    send_to_client(state, {
                        type = "npc_message",
                        speaker = npc.name,
                        npc_id = npc.id,
                        content = response,
                        color = npc.color,
                    })
                    table.insert(new_speakers, npc.id)
                    spoke_ids[npc.id] = true
                end
            end
        end
    end

    -- Main patron
    if not spoke_ids["main"] then
        local chance
        if depth == 0 then
            chance = MAIN_INTERJECTION_CHANCE
        else
            chance = NPC_REACTION_CHANCE * chance_multiplier
        end

        if math.random() < chance then
            local last_npc_entry = nil
            if depth > 0 then
                for i = #state.chat_log, 1, -1 do
                    if state.chat_log[i].kind == "npc" and state.chat_log[i].npc_id ~= "main" then
                        last_npc_entry = state.chat_log[i]
                        break
                    end
                end
            end

            local prompt
            if depth > 0 and last_npc_entry then
                prompt = prompts.build_main_reaction_prompt(state.character, last_npc_entry.speaker, state.language)
                send_to_client(state, { type = "status", text = state.character.name .. " turns to " .. last_npc_entry.speaker .. "..." })
            else
                prompt = prompts.build_main_interjection_prompt(state.character, state.language)
                send_to_client(state, { type = "status", text = state.character.name .. " chimes in..." })
            end

            local msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), "main")
            local response = ask_agent_safe(state, prompt, msgs)

            if response then
                table.insert(state.chat_log, {
                    speaker = state.character.name,
                    kind = "npc",
                    npc_id = "main",
                    content = response,
                })
                send_to_client(state, {
                    type = "npc_message",
                    speaker = state.character.name,
                    npc_id = "main",
                    content = response,
                    color = MAIN_NPC_COLOR,
                })
                table.insert(new_speakers, "main")
                spoke_ids["main"] = true
            end
        end
    end

    -- If anyone new spoke, give others a chance to chain-react
    if #new_speakers > 0 then
        try_interjections(state, spoke_ids, depth + 1)
    end
end

-- ════════════════════════════════════════════════════════════
-- Command handling
-- ════════════════════════════════════════════════════════════

local function handle_command(state, content)
    local cmd = content.command or ""
    local value = content.value or ""

    if cmd == "new" then
        state.character = prompts.generate_character()
        state.system_prompt = prompts.build_main_prompt(state.character, state.language)
        state.chat_log = {}

        table.insert(state.chat_log, {
            speaker = "You",
            kind = "player",
            npc_id = nil,
            content = "[You finish your drink and move to another seat...]",
        })

        sync_npcs(state)

        local npc_info = {}
        for _, npc in ipairs(state.registry_npcs) do
            table.insert(npc_info, { id = npc.id, name = npc.name, role = npc.role, color = npc.color })
        end
        send_to_client(state, {
            type = "new_character",
            character = state.character,
            npcs = npc_info,
        })

        -- Generate greeting from new patron
        send_to_client(state, { type = "status", text = state.character.name .. " notices you..." })
        local msgs = prompts.build_llm_messages(state.chat_log, "main")
        local greeting = ask_agent_safe(state, state.system_prompt, msgs)

        if greeting then
            table.insert(state.chat_log, {
                speaker = state.character.name,
                kind = "npc",
                npc_id = "main",
                content = greeting,
            })
            send_to_client(state, {
                type = "npc_message",
                speaker = state.character.name,
                npc_id = "main",
                content = greeting,
                color = MAIN_NPC_COLOR,
            })
            try_interjections(state, { ["main"] = true }, 0)
        end

        send_to_client(state, { type = "status" })

    elseif cmd == "look" then
        local npc_info = {}
        for _, npc in ipairs(state.registry_npcs) do
            table.insert(npc_info, { id = npc.id, name = npc.name, role = npc.role, color = npc.color })
        end
        send_to_client(state, {
            type = "character_info",
            character = state.character,
            npcs = npc_info,
        })

    elseif cmd == "lang" then
        if value and value ~= "" then
            state.language = value
            send_to_client(state, {
                type = "system",
                content = "Language set to " .. state.language .. ". New conversations will use this language.",
            })
        else
            send_to_client(state, {
                type = "system",
                content = "Current language: " .. state.language .. ". Usage: /lang <language>",
            })
        end

    elseif cmd == "help" then
        send_to_client(state, {
            type = "system",
            content = "Commands: /new (new character), /look (who's around), /lang <language> (set language), /help (this message), /quit (leave tavern). Tip: address someone by name to talk to them directly.",
        })

    elseif cmd == "quit" then
        send_to_client(state, {
            type = "system",
            content = "*You push back your stool and head for the door. The sounds of the tavern fade behind you...*",
        })
        if state.client_pid then
            process.send(state.client_pid, "ws.close", {
                code = 1000,
                reason = "Player quit",
            })
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- Chat message handling
-- ════════════════════════════════════════════════════════════

local function handle_chat(state, text)
    -- Sync NPCs (arrivals/departures handled by event subscription)
    sync_npcs(state)

    -- Echo player message
    table.insert(state.chat_log, {
        speaker = "You",
        kind = "player",
        npc_id = nil,
        content = text,
    })
    send_to_client(state, { type = "player_message", speaker = "You", content = text })

    -- Route
    send_to_client(state, { type = "status", text = "Routing..." })
    local targets = ask_router(state, text)

    local spoke_ids = {}

    -- Generate responses for each target
    for _, target_id in ipairs(targets) do
        local responder_npc = find_npc_by_id(state.registry_npcs, target_id)

        if target_id == "main" or not responder_npc then
            -- Main patron responds
            send_to_client(state, { type = "status", text = state.character.name .. " is thinking..." })

            local llm_msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), "main")
            local response = ask_agent_safe(state, state.system_prompt, llm_msgs)

            if response then
                table.insert(state.chat_log, {
                    speaker = state.character.name,
                    kind = "npc",
                    npc_id = "main",
                    content = response,
                })
                send_to_client(state, {
                    type = "npc_message",
                    speaker = state.character.name,
                    npc_id = "main",
                    content = response,
                    color = MAIN_NPC_COLOR,
                })
                spoke_ids["main"] = true
            end
        else
            -- Registry NPC responds
            send_to_client(state, { type = "status", text = responder_npc.name .. " is thinking..." })

            local prompt = prompts.build_addressed_prompt(responder_npc, state.language)
            local llm_msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), responder_npc.id)
            local response = ask_agent_safe(state, prompt, llm_msgs)

            if response then
                table.insert(state.chat_log, {
                    speaker = responder_npc.name,
                    kind = "npc",
                    npc_id = responder_npc.id,
                    content = response,
                })
                send_to_client(state, {
                    type = "npc_message",
                    speaker = responder_npc.name,
                    npc_id = responder_npc.id,
                    content = response,
                    color = responder_npc.color,
                })
                spoke_ids[responder_npc.id] = true
            end
        end
    end

    -- Interjections
    try_interjections(state, spoke_ids, 0)

    -- Clear status
    send_to_client(state, { type = "status" })
end

-- ════════════════════════════════════════════════════════════
-- WebSocket lifecycle handlers
-- ════════════════════════════════════════════════════════════

local function handle_join(state, data)
    state.client_pid = data.client_pid
    logger:info("session joined", { client_pid = data.client_pid })

    -- Generate character
    math.randomseed(math.floor(os.time()) + math.random(1, 10000))
    state.character = prompts.generate_character()
    state.language = "English"
    state.chat_log = {}
    state.system_prompt = prompts.build_main_prompt(state.character, state.language)

    -- Load NPCs
    state.registry_npcs = load_registry_npcs(state)

    -- Send greeting with character + NPC info
    local npc_info = {}
    for _, npc in ipairs(state.registry_npcs) do
        table.insert(npc_info, { id = npc.id, name = npc.name, role = npc.role, color = npc.color })
    end
    send_to_client(state, {
        type = "greeting",
        character = state.character,
        npcs = npc_info,
    })

    -- Initial sit-down
    table.insert(state.chat_log, {
        speaker = "You",
        kind = "player",
        npc_id = nil,
        content = "[You sit down at the bar next to this person.]",
    })

    -- Generate NPC greeting
    send_to_client(state, { type = "status", text = state.character.name .. " notices you..." })
    local msgs = prompts.build_llm_messages(state.chat_log, "main")
    local greeting = ask_agent_safe(state, state.system_prompt, msgs)

    if greeting then
        table.insert(state.chat_log, {
            speaker = state.character.name,
            kind = "npc",
            npc_id = "main",
            content = greeting,
        })
        send_to_client(state, {
            type = "npc_message",
            speaker = state.character.name,
            npc_id = "main",
            content = greeting,
            color = MAIN_NPC_COLOR,
        })
        try_interjections(state, { ["main"] = true }, 0)
    end

    send_to_client(state, { type = "status" })
end

local function handle_message(state, data)
    -- Relay delivers data in varying structures — normalize to get the raw JSON string
    local raw
    if type(data.data) == "string" and data.data ~= "" then
        raw = data.data
    elseif type(data) == "string" then
        raw = data
    else
        raw = json.encode(data)
    end

    local ok, content = pcall(json.decode, raw)
    if not ok or not content then
        logger:warn("invalid JSON from client", { raw = tostring(raw) })
        return
    end

    if content.type == "command" then
        handle_command(state, content)
    elseif content.type == "chat" and content.text and content.text ~= "" then
        handle_chat(state, content.text)
    end
end

-- ════════════════════════════════════════════════════════════
-- Idle chatter — NPCs talk to each other when player is quiet
-- ════════════════════════════════════════════════════════════

local function try_idle_chatter(state)
    if #state.registry_npcs == 0 or not state.character then
        return
    end

    -- Build candidate list: registry NPCs + main patron
    local candidates = {}
    for _, npc in ipairs(state.registry_npcs) do
        table.insert(candidates, npc)
    end

    -- Pick a random NPC to start talking
    local starter = candidates[math.random(1, #candidates)]
    if not starter then return end

    -- Build names of others present
    local other_names = {}
    for _, c in ipairs(candidates) do
        if c.id ~= starter.id then
            table.insert(other_names, c.name)
        end
    end
    table.insert(other_names, state.character.name)

    -- Use interjection prompt (they're just breaking the silence)
    local prompt = prompts.build_interjection_prompt(starter, state.language)
    send_to_client(state, { type = "status", text = starter.name .. " breaks the silence..." })

    local msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), starter.id)
    local response = ask_agent_safe(state, prompt, msgs)

    if response then
        table.insert(state.chat_log, {
            speaker = starter.name,
            kind = "npc",
            npc_id = starter.id,
            content = response,
        })
        send_to_client(state, {
            type = "npc_message",
            speaker = starter.name,
            npc_id = starter.id,
            content = response,
            color = starter.color,
        })

        -- Let others react to the idle chatter
        local spoke_ids = { [starter.id] = true }
        try_interjections(state, spoke_ids, 1)
    end

    send_to_client(state, { type = "status" })
end

-- ════════════════════════════════════════════════════════════
-- NPC arrival/departure event handler
-- ════════════════════════════════════════════════════════════

local function handle_npc_event(state, evt)
    if not state.character then return end

    local event_type = evt.kind
    local npc_name = evt.data and evt.data.name or nil

    -- Sync registry to pick up the change
    sync_npcs(state)

    -- On departure, 70% chance someone says goodbye
    if event_type == "departure" and npc_name and math.random() < FAREWELL_CHANCE then
        -- Pick a random present NPC (or main patron) to say goodbye
        local candidates = {}
        for _, npc in ipairs(state.registry_npcs) do
            table.insert(candidates, npc)
        end

        -- Also the main patron can say bye
        if math.random() < 0.5 then
            send_to_client(state, { type = "status", text = state.character.name .. " waves..." })
            local prompt = prompts.build_main_farewell_prompt(state.character, npc_name, state.language)
            local msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), "main")
            local response = ask_agent_safe(state, prompt, msgs)
            if response then
                table.insert(state.chat_log, {
                    speaker = state.character.name,
                    kind = "npc",
                    npc_id = "main",
                    content = response,
                })
                send_to_client(state, {
                    type = "npc_message",
                    speaker = state.character.name,
                    npc_id = "main",
                    content = response,
                    color = MAIN_NPC_COLOR,
                })
            end
        elseif #candidates > 0 then
            local npc = candidates[math.random(1, #candidates)]
            if npc then
                send_to_client(state, { type = "status", text = npc.name .. " waves..." })
                local prompt = prompts.build_farewell_prompt(npc, npc_name, state.language)
                local msgs = prompts.build_llm_messages(get_llm_window(state.chat_log), npc.id)
                local response = ask_agent_safe(state, prompt, msgs)
                if response then
                    table.insert(state.chat_log, {
                        speaker = npc.name,
                        kind = "npc",
                        npc_id = npc.id,
                        content = response,
                    })
                    send_to_client(state, {
                        type = "npc_message",
                        speaker = npc.name,
                        npc_id = npc.id,
                        content = response,
                        color = npc.color,
                    })
                end
            end
        end
        send_to_client(state, { type = "status" })

    elseif event_type == "arrival" then
        -- Arrivals: let existing NPCs react (already handled by sync_npcs system messages)
        try_interjections(state, {}, 1)
        send_to_client(state, { type = "status" })
    end
end

-- ════════════════════════════════════════════════════════════
-- Main process loop
-- ════════════════════════════════════════════════════════════

local function main()
    local state = {
        client_pid = nil,
        character = nil,
        chat_log = {},
        registry_npcs = {},
        language = "English",
        system_prompt = nil,
        npc_color_map = {},
        npc_color_idx = 0,
        idle_warning = false,
    }

    local proc_events = process.events()
    local inbox = process.inbox()
    local idle_timer = time.after(IDLE_TIMEOUT)
    local chatter_timer = time.after(IDLE_CHATTER_DELAY)
    local npc_sub = events.subscribe("bar.npc")
    local npc_channel = npc_sub:channel()

    logger:info("session process started")

    while true do
        local r = channel.select {
            proc_events:case_receive(),
            inbox:case_receive(),
            idle_timer:case_receive(),
            chatter_timer:case_receive(),
            npc_channel:case_receive(),
        }

        if r.channel == proc_events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                if state.client_pid then
                    send_to_client(state, {
                        type = "system",
                        content = "*The tavern is closing for the night...*",
                    })
                    process.send(state.client_pid, "ws.close", {
                        code = 1001,
                        reason = "Server shutting down",
                    })
                end
                logger:info("session shutting down")
                return 0
            end

        elseif r.channel == idle_timer then
            if state.idle_warning then
                send_to_client(state, {
                    type = "system",
                    content = "*You drift off to sleep at the bar...*",
                })
                if state.client_pid then
                    process.send(state.client_pid, "ws.close", {
                        code = 1000,
                        reason = "Idle timeout",
                    })
                end
                return 0
            else
                send_to_client(state, {
                    type = "system",
                    content = "*You've been sitting quietly for a while. The bartender glances over...*",
                })
                idle_timer = time.after("60s")
                state.idle_warning = true
            end

        elseif r.channel == chatter_timer then
            -- NPCs may start chatting when player is quiet
            if state.character and #state.registry_npcs > 0 and math.random() < IDLE_CHATTER_CHANCE then
                sync_npcs(state)
                try_idle_chatter(state)
            end
            chatter_timer = time.after(IDLE_CHATTER_DELAY)

        elseif r.channel == npc_channel then
            -- NPC arrived or departed — react immediately
            local evt = r.value
            handle_npc_event(state, evt)

        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()

            -- Reset timers on real messages (not heartbeats)
            if topic ~= "ws.heartbeat" then
                idle_timer = time.after(IDLE_TIMEOUT)
                chatter_timer = time.after(IDLE_CHATTER_DELAY)
                state.idle_warning = false
            end
            local data = msg:payload():data()

            if topic == "ws.join" then
                handle_join(state, data)
            elseif topic == "ws.message" then
                handle_message(state, data)
            elseif topic == "ws.leave" then
                logger:info("session left", { client_pid = data.client_pid })
                return 0
            elseif topic == "ws.heartbeat" then
                -- Keep-alive only, timers not reset (so chatter can still fire)
            end
        end
    end
end

return { main = main }
