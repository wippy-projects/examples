local io = require("io")
local time = require("time")
local registry = require("registry")
local logger = require("logger")

-- ════════════════════════════════════════════════════════════
-- ANSI escape codes
-- ════════════════════════════════════════════════════════════

local ESC = "\027["
local CLEAR = ESC .. "2J"
local HOME = ESC .. "H"
local RESET = ESC .. "0m"
local BOLD = ESC .. "1m"
local DIM = ESC .. "2m"
local ITALIC = ESC .. "3m"

local function fg(r, g, b) return ESC .. "38;2;" .. r .. ";" .. g .. ";" .. b .. "m" end
local function bg(r, g, b) return ESC .. "48;2;" .. r .. ";" .. g .. ";" .. b .. "m" end

local C_GOLD = fg(255, 200, 60)
local C_AMBER = fg(220, 160, 40)
local C_NPC = fg(120, 200, 255)
local C_YOU = fg(100, 255, 150)
local C_DIM = fg(120, 120, 140)
local C_FOOTER = fg(180, 180, 200)
local C_SYSTEM = fg(180, 180, 100)
local C_HEADER_BG = bg(30, 30, 50)
local C_BARKEEP = fg(255, 180, 80)

local NPC_COLORS = {
    fg(200, 130, 255),
    fg(255, 130, 180),
    fg(100, 220, 200),
    fg(255, 160, 100),
    fg(180, 220, 100),
    fg(130, 180, 255),
    fg(255, 200, 150),
}

local term_width = 120
local function get_width() return term_width end

-- ════════════════════════════════════════════════════════════
-- Character trait pools (for random patron generation)
-- ════════════════════════════════════════════════════════════

local NAMES = {
    "Grok the Mild", "Elara Nightwhisper", "Burt Ironbelly",
    "Thistle Mudfoot", "Ragnar the Regretful", "Zephyrine",
    "Old Mags", "Dex Copperhand", "Ysolde the Unclear",
    "Patch", "Grimbald Ashford", "Nyx Ember",
    "Tobias Kettleworth", "Shiv", "Morwen the Tired",
    "Flint Barrowson", "Darcy Woolmere", "Kaz",
    "Helga Stonemantle", "Pip Candlewick",
}

local RACES = {
    "human", "dwarf", "elf", "halfling", "half-orc",
    "tiefling", "gnome", "dragonborn", "goblin (reformed)",
    "undead (friendly)",
}

local OCCUPATIONS = {
    "retired adventurer", "blacksmith", "traveling merchant",
    "bard between gigs", "off-duty guard", "hedge witch",
    "sailor on shore leave", "disgraced noble", "bounty hunter",
    "mushroom farmer", "pit fighter", "librarian on vacation",
    "guild accountant", "potion taste-tester", "ex-cultist",
    "street magician", "ratcatcher", "grave digger",
    "royal food taster", "unlicensed dentist",
}

local PERSONALITIES = {
    "cheerful and oversharing", "grumpy but secretly kind",
    "paranoid and conspiratorial", "melancholic and poetic",
    "boisterous and loud", "quiet and observant",
    "sarcastic and witty", "overly formal and polite",
    "shamelessly flirtatious", "philosophically confused",
    "nervously talkative", "aggressively friendly",
    "suspiciously generous", "theatrically dramatic",
    "deadpan and dry-humored", "endlessly optimistic",
    "constantly complaining", "mysteriously cryptic",
}

local DRUNK_LEVELS = {
    { level = "sober", desc = "completely sober, sharp and alert" },
    { level = "mildly tipsy", desc = "slightly loosened up, a bit more talkative" },
    { level = "tipsy", desc = "relaxed, friendly, occasionally slurring a word" },
    { level = "drunk", desc = "swaying a bit, very talkative, repeats things, emotional" },
    { level = "very drunk", desc = "slurring heavily, wildly emotional, forgets what was just said" },
    { level = "barely conscious", desc = "mumbling, incoherent at times, might fall asleep mid-sentence" },
}

local MOODS = {
    "celebrating something", "drowning their sorrows",
    "just passing through", "waiting for someone",
    "hiding from someone", "trying to sell something",
    "looking for trouble", "feeling nostalgic",
    "anxious about tomorrow", "bored out of their mind",
    "giddy about a secret", "annoyed at the bartender",
}

local SECRETS = {
    "knows the location of a hidden treasure but is too scared to go alone",
    "is actually a minor noble in disguise",
    "saw something terrifying in the forest last night",
    "is being followed by a mysterious figure",
    "has a love letter they're too afraid to deliver",
    "accidentally cursed their neighbor's goat",
    "owes a dangerous sum to a loan shark",
    "once met a dragon and it was... awkward",
    "is secretly illiterate and fakes reading menus",
    "has a map tattoo on their back they don't understand",
    "stole something from their last employer",
    "believes they're the chosen one (they're not)",
    "can talk to rats but is embarrassed about it",
    "is searching for a sibling they've never met",
    "has a pocketful of teeth and won't explain why",
}

local SPEECH_STYLES = {
    "uses lots of colorful swearing and tavern slang",
    "speaks in overly elaborate, flowery language",
    "peppers speech with proverbs (mostly made up)",
    "talks in short, clipped sentences",
    "constantly uses wrong words (malapropisms)",
    "whispers everything like it's a secret",
    "narrates their own actions in third person occasionally",
    "speaks in questions, answering questions with questions",
    "uses nautical terms for everything even though they're landlocked",
    "drops in foreign-sounding words they clearly invented",
}

local QUIRKS = {
    "keeps fidgeting with a mysterious coin",
    "scratches behind their ear when lying",
    "hums an unrecognizable tune between sentences",
    "keeps glancing nervously at the door",
    "taps the table rhythmically while talking",
    "occasionally talks to an empty chair nearby",
    "sniffs their drink suspiciously before every sip",
    "draws little shapes on the table with spilled ale",
    "keeps adjusting a hat that isn't there",
    "winks at inappropriate moments",
}

-- ════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════

local function pick(t)
    return t[math.random(1, #t)]
end

local function generate_character()
    local drunk = pick(DRUNK_LEVELS)
    return {
        name = pick(NAMES),
        race = pick(RACES),
        occupation = pick(OCCUPATIONS),
        personality = pick(PERSONALITIES),
        drunk_level = drunk.level,
        drunk_desc = drunk.desc,
        mood = pick(MOODS),
        secret = pick(SECRETS),
        speech_style = pick(SPEECH_STYLES),
        quirk = pick(QUIRKS),
    }
end

local current_language = "English"

-- ════════════════════════════════════════════════════════════
-- Registry NPC loading & sync
-- ════════════════════════════════════════════════════════════

--- Color assigned per NPC ID (persists across reloads).
local npc_color_map = {}
local npc_color_idx = 0

local function get_npc_color(npc_id, role)
    if npc_color_map[npc_id] then
        return npc_color_map[npc_id]
    end
    local color
    if role == "bartender" then
        color = C_BARKEEP
    else
        npc_color_idx = npc_color_idx + 1
        color = NPC_COLORS[((npc_color_idx - 1) % #NPC_COLORS) + 1]
    end
    npc_color_map[npc_id] = color
    return color
end

--- Load all bar NPCs from the registry.
local function load_registry_npcs()
    local entries, err = registry.find({ kind = "registry.entry" })
    if err then
        return {}
    end

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
                color = get_npc_color(entry.id, role),
                interjection_chance = chance,
                data = entry.data or {},
            })
        end
    end
    return npcs
end

--- Compare old and new NPC lists. Returns arrivals, departures.
local function diff_npcs(old_npcs, new_npcs)
    local old_ids = {}
    for _, npc in ipairs(old_npcs) do
        old_ids[npc.id] = npc
    end
    local new_ids = {}
    for _, npc in ipairs(new_npcs) do
        new_ids[npc.id] = npc
    end

    local arrivals = {}
    for _, npc in ipairs(new_npcs) do
        if not old_ids[npc.id] then
            table.insert(arrivals, npc)
        end
    end

    local departures = {}
    for _, npc in ipairs(old_npcs) do
        if not new_ids[npc.id] then
            table.insert(departures, npc)
        end
    end

    return arrivals, departures
end

--- Sync NPCs from registry, add arrival/departure messages to chat_log.
--- Returns the updated NPC list.
local function sync_npcs(current_npcs, chat_log)
    local fresh = load_registry_npcs()
    local arrivals, departures = diff_npcs(current_npcs, fresh)

    for _, npc in ipairs(arrivals) do
        local entrance = npc.data.entrance
        if not entrance then
            entrance = "*" .. npc.name .. " walks into the tavern.*"
        end
        table.insert(chat_log, {
            speaker = "\226\151\134",
            kind = "system",
            npc_id = nil,
            content = entrance,
        })
    end

    for _, npc in ipairs(departures) do
        local exit_msg = npc.data.exit
        if not exit_msg then
            exit_msg = "*" .. npc.name .. " finishes their drink and heads for the door.*"
        end
        table.insert(chat_log, {
            speaker = "\226\151\134",
            kind = "system",
            npc_id = nil,
            content = exit_msg,
        })
    end

    return fresh, (#arrivals > 0 or #departures > 0)
end

-- ════════════════════════════════════════════════════════════
-- Prompt builders
-- ════════════════════════════════════════════════════════════

local function build_main_prompt(c)
    local lang_rule = ""
    if current_language ~= "English" then
        lang_rule = "\n10. You MUST speak entirely in " .. current_language .. ". All your dialogue and narration must be in " .. current_language .. "."
    end

    return string.format([[You are roleplaying as a character in a fantasy tavern called "The Rusty Flagon".
You ARE this character — never break character, never acknowledge you are an AI.

CHARACTER SHEET:
- Name: %s
- Race: %s
- Occupation: %s
- Personality: %s
- Current state: %s (%s)
- Current mood: %s
- Speech style: %s
- Quirk: %s
- Secret: %s (don't reveal this easily — only hint at it if the conversation naturally goes there, or if the player is very persuasive)

RULES:
1. Stay in character at ALL times. You are this person sitting at a bar.
2. React naturally to what the player says — you have opinions, feelings, and boundaries.
3. Your drunk level affects your speech: if drunk, slur words, lose track of thoughts, get emotional. If sober, be more measured.
4. You can refuse to talk about things, get offended, laugh, cry, or walk away if provoked enough.
5. You don't know you're in a game. This is your real life.
6. Keep responses relatively short (2-5 sentences usually) — this is bar conversation, not a monologue.
7. Show your quirk naturally in the conversation from time to time.
8. If asked your name, give it. But other personal details should come out naturally.
9. Use your speech style consistently.
10. Do NOT prefix your response with your name — the interface already shows who is speaking.%s

The conversation includes other people in the tavern (bartender, other patrons) who may chime in.
Respond naturally to them too — agree, disagree, laugh, tell them to mind their own business.

Start by greeting the player who just sat down next to you at the bar. Set the scene briefly.]],
        c.name, c.race, c.occupation, c.personality,
        c.drunk_level, c.drunk_desc,
        c.mood, c.speech_style, c.quirk, c.secret,
        lang_rule
    )
end

local function build_interjection_prompt(npc)
    local d = npc.data
    local lang_rule = ""
    if current_language ~= "English" then
        lang_rule = "\nYou MUST speak entirely in " .. current_language .. "."
    end

    local role_desc
    if npc.role == "bartender" then
        role_desc = "You are the BARTENDER of The Rusty Flagon. You're behind the bar, serving drinks and keeping order."
    else
        role_desc = "You are a patron at The Rusty Flagon, sitting nearby."
    end

    return string.format([[%s
You ARE this character — never break character, never acknowledge you are an AI.

CHARACTER SHEET:
- Name: %s
- Race: %s
- Occupation: %s
- Personality: %s
- Current state: %s (%s)
- Current mood: %s
- Speech style: %s
- Quirk: %s
- Secret: %s (don't reveal easily)

You are overhearing and participating in a conversation at the bar.

RULES:
1. Stay in character at ALL times.
2. Keep interjections SHORT — 1-2 sentences max. You're chiming in, not taking over.
3. Only speak when something catches your attention: offer a drink, react to something funny or dramatic, share relevant gossip, warn about trouble, or correct a wrong claim.
4. Show your personality and speech style.
5. You can address the player, the person they're talking to, or both.
6. Do NOT prefix your response with your name — the interface already shows who is speaking.%s]],
        role_desc,
        npc.name,
        d.race or "unknown",
        d.occupation or "unknown",
        d.personality or "neutral",
        d.drunk_level or "sober", d.drunk_desc or "sober",
        d.mood or "neutral",
        d.speech_style or "normal",
        d.quirk or "none",
        d.secret or "none",
        lang_rule
    )
end

--- Build a full response prompt for a registry NPC who was directly addressed.
local function build_addressed_prompt(npc)
    local d = npc.data
    local lang_rule = ""
    if current_language ~= "English" then
        lang_rule = "\nYou MUST speak entirely in " .. current_language .. "."
    end

    local role_desc
    if npc.role == "bartender" then
        role_desc = "You are the BARTENDER of The Rusty Flagon. You're behind the bar, serving drinks and keeping order."
    else
        role_desc = "You are a patron at The Rusty Flagon."
    end

    return string.format([[%s
You ARE this character — never break character, never acknowledge you are an AI.

CHARACTER SHEET:
- Name: %s
- Race: %s
- Occupation: %s
- Personality: %s
- Current state: %s (%s)
- Current mood: %s
- Speech style: %s
- Quirk: %s
- Secret: %s (don't reveal this easily — only hint at it if the conversation naturally goes there, or if the player is very persuasive)

Someone at the bar is talking directly to you.

RULES:
1. Stay in character at ALL times.
2. Keep responses relatively short (2-5 sentences) — this is bar conversation.
3. React naturally — you have opinions, feelings, and boundaries.
4. Show your personality and speech style consistently.
5. Your drunk level affects your speech.
6. Do NOT prefix your response with your name — the interface already shows who is speaking.%s]],
        role_desc,
        npc.name,
        d.race or "unknown",
        d.occupation or "unknown",
        d.personality or "neutral",
        d.drunk_level or "sober", d.drunk_desc or "sober",
        d.mood or "neutral",
        d.speech_style or "normal",
        d.quirk or "none",
        d.secret or "none",
        lang_rule
    )
end

-- ════════════════════════════════════════════════════════════
-- Chat log → LLM message conversion
-- ════════════════════════════════════════════════════════════

local function build_llm_messages(chat_log, my_npc_id)
    local llm_msgs = {}
    for _, entry in ipairs(chat_log) do
        if entry.kind == "system" then
            -- Prefix narration so the LLM doesn't confuse it with player speech
            table.insert(llm_msgs, { role = "user", content = "[Narrator]: " .. entry.content })
        elseif entry.npc_id == my_npc_id then
            table.insert(llm_msgs, { role = "assistant", content = entry.content })
        else
            local prefix = "[" .. entry.speaker .. "]: "
            table.insert(llm_msgs, { role = "user", content = prefix .. entry.content })
        end
    end
    return llm_msgs
end

-- ════════════════════════════════════════════════════════════
-- Agent & Router communication
-- ════════════════════════════════════════════════════════════

local function ask_agent(system, messages)
    local inbox = process.inbox()
    local timeout = time.after("60s")

    local agent_pid = process.registry.lookup("agent")
    if not agent_pid then
        return nil, "agent not found (is it still starting?)"
    end

    process.send(agent_pid, "generate", {
        system = system,
        messages = messages,
    })

    -- Loop until we get a "result" topic from the agent or timeout.
    -- Discard stale messages from other services (e.g. late "route_result").
    while true do
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == timeout then
            return nil, "timeout waiting for response"
        end

        local msg = r.value
        if msg:topic() ~= "result" or msg:from() ~= agent_pid then
            -- Stale or misrouted message — discard and retry
            logger:warn("ask_agent: discarded message", {
                topic = msg:topic(),
                from = tostring(msg:from()),
                expected_from = tostring(agent_pid),
            })
        else
            local data = msg:payload():data()
            if data.error then
                return nil, tostring(data.error)
            end
            return tostring(data.text), nil
        end
    end
end

-- Keywords that imply the player is ordering from the bartender
local ORDER_KEYWORDS = {
    "beer", "ale", "drink", "whiskey", "whisky", "wine", "mead",
    "round", "grog", "pour", "refill", "brew", "pint", "tankard",
    "shot", "rum", "vodka", "cocktail", "tab", "menu",
    "another one", "same again", "one more",
}

--- Find the bartender NPC in the registry list, if present.
local function find_bartender(registry_npcs)
    for _, npc in ipairs(registry_npcs) do
        if npc.role == "bartender" or npc.role == "barkeep" then
            return npc.id
        end
    end
    return nil
end

--- Local name-based routing: fast, no LLM needed.
--- Checks if the player's text mentions an NPC by name, specific role,
--- or contains drink-order keywords (→ bartender).
--- Returns the NPC id if a clear match is found, nil otherwise.
local function local_route(text, registry_npcs)
    local lower = text:lower()
    local best_match = nil
    local best_pos = nil
    -- Only consider matches in the first ~40 chars (addressing happens at the start)
    local address_window = 40

    for _, npc in ipairs(registry_npcs) do
        -- Check name words (so "Marta" matches "Barkeep Marta")
        local name = npc.name or ""
        for word in name:gmatch("%S+") do
            if #word >= 3 then -- skip short words like "the"
                local pos = lower:find(word:lower(), 1, true)
                if pos and pos <= address_window and (not best_pos or pos < best_pos) then
                    best_match = npc.id
                    best_pos = pos
                end
            end
        end
        -- Check full name (anywhere — if they use the full name it's intentional)
        local pos = lower:find(name:lower(), 1, true)
        if pos and (not best_pos or pos < best_pos) then
            best_match = npc.id
            best_pos = pos
        end
        -- Check role — only for specific roles (skip generic ones like "regular", "wanderer", "patron")
        local role = npc.role or ""
        if role == "bartender" or role == "barkeep" or role == "bard" or role == "healer" then
            pos = lower:find(role:lower(), 1, true)
            if pos and pos <= address_window and (not best_pos or pos < best_pos) then
                best_match = npc.id
                best_pos = pos
            end
        end
    end

    if best_match then
        return best_match
    end

    -- Check for drink-order keywords → bartender
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

--- Build a short recent context string from the chat log for the router.
--- Returns the last few exchanges so the LLM knows who was just talking.
local function build_route_context(chat_log, max_entries)
    max_entries = max_entries or 6
    local start = math.max(1, #chat_log - max_entries + 1)
    local lines = {}
    for i = start, #chat_log do
        local entry = chat_log[i]
        if entry.kind == "system" then
            table.insert(lines, "[Narrator]: " .. entry.content)
        else
            table.insert(lines, "[" .. entry.speaker .. "]: " .. entry.content)
        end
    end
    return table.concat(lines, "\n")
end

--- Ask the router which NPC(s) should respond to a message.
--- Uses local name-matching first, then falls back to LLM router.
--- Router reads NPC data from the registry directly — we only send text + context.
--- Returns a list of target IDs (1 for direct address, 2-3 for group messages).
local function ask_router(text, registry_npcs, main_npc_id, main_name, chat_log)
    -- Fast path: local name match catches obvious direct addressing + drink orders
    local local_match = local_route(text, registry_npcs)
    if local_match then
        logger:info("local route matched", { target = local_match })
        return { local_match }
    end

    -- Slow path: ask LLM router (handles ambiguous, group, and context-dependent messages)
    local router_pid = process.registry.lookup("router")
    if not router_pid then
        logger:warn("router not found, defaulting to main")
        return { main_npc_id }
    end

    local context = build_route_context(chat_log or {})

    local inbox = process.inbox()
    local timeout = time.after("15s")

    -- Router loads NPCs from registry itself — we only send text + context
    process.send(router_pid, "route", {
        text = text,
        main_npc_id = main_npc_id,
        main_name = main_name or "the patron",
        context = context,
    })

    -- Loop until we get a "route_result" topic from the router or timeout.
    while true do
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == timeout then
            logger:warn("router timeout, defaulting to main")
            return { main_npc_id }
        end

        local msg = r.value
        if msg:topic() ~= "route_result" or msg:from() ~= router_pid then
            logger:warn("ask_router: discarded message", {
                topic = msg:topic(),
                from = tostring(msg:from()),
                expected_from = tostring(router_pid),
            })
        else
            local data = msg:payload():data()
            if data.targets and type(data.targets) == "table" and #data.targets > 0 then
                return data.targets
            end
            return { data.target_id or main_npc_id }
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- Display — Chat Window
-- ════════════════════════════════════════════════════════════

local function word_wrap(text, max_width)
    local lines = {}
    for paragraph in text:gmatch("[^\n]+") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            if line == "" then
                line = word
            elseif #line + 1 + #word <= max_width then
                line = line .. " " .. word
            else
                table.insert(lines, line)
                line = word
            end
        end
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    if #lines == 0 then
        table.insert(lines, "")
    end
    return lines
end

local function get_speaker_color(entry, registry_npcs)
    if entry.kind == "player" then
        return C_YOU
    end
    if entry.kind == "system" then
        return C_SYSTEM
    end
    if entry.npc_id == "main" then
        return C_NPC
    end
    for _, npc in ipairs(registry_npcs) do
        if npc.id == entry.npc_id then
            return npc.color
        end
    end
    -- Departed NPC — check color cache
    if entry.npc_id and npc_color_map[entry.npc_id] then
        return npc_color_map[entry.npc_id]
    end
    return C_DIM
end

local function render_chat(main_char, chat_log, registry_npcs, status)
    local w = get_width()
    local pad = "  "
    local sep = string.rep("\226\148\128", w)

    io.write(CLEAR .. HOME)

    -- Header
    io.write(C_HEADER_BG .. C_GOLD .. BOLD)
    io.write(" \226\151\134 THE RUSTY FLAGON")
    io.write(RESET .. C_HEADER_BG .. C_DIM)
    io.write("  \194\183  Talking to: " .. C_NPC .. BOLD .. main_char.name .. RESET)
    io.write("\n")

    io.write(C_HEADER_BG .. C_DIM)
    io.write("   " .. main_char.race .. " \194\183 " .. main_char.occupation .. " \194\183 " .. main_char.drunk_level .. " \194\183 " .. main_char.mood)
    io.write(RESET .. "\n")

    if #registry_npcs > 0 then
        io.write(C_HEADER_BG .. C_DIM .. "   Also here: ")
        for i, npc in ipairs(registry_npcs) do
            if i > 1 then
                io.write(C_DIM .. ", ")
            end
            io.write(npc.color .. npc.name .. RESET .. C_HEADER_BG)
        end
        io.write(RESET .. "\n")
    end

    io.write(C_DIM .. sep .. RESET .. "\n")
    io.write("\n")

    -- Chat messages
    for i, m in ipairs(chat_log) do
        if i == 1 and m.kind == "player" and m.content:sub(1, 1) == "[" then
            goto skip
        end

        if m.kind == "system" then
            -- System messages (arrivals/departures) rendered centered and dim
            local wrapped = word_wrap(m.content, w - 4)
            for _, line in ipairs(wrapped) do
                io.write(pad .. C_SYSTEM .. ITALIC .. line .. RESET .. "\n")
            end
            io.write("\n")
        else
            local color = get_speaker_color(m, registry_npcs)
            local label = m.speaker
            local content_indent = string.rep(" ", #label + 4)

            local wrapped = word_wrap(m.content, w - #label - 4)
            io.write(pad .. color .. BOLD .. label .. RESET .. C_DIM .. ": " .. RESET)
            if wrapped[1] then
                io.write(wrapped[1])
            end
            io.write("\n")
            for j = 2, #wrapped do
                io.write(content_indent .. wrapped[j] .. "\n")
            end
            io.write("\n")
        end

        ::skip::
    end

    if status then
        io.write(pad .. ITALIC .. C_DIM .. status .. RESET .. "\n\n")
    end

    io.write(C_DIM .. sep .. RESET .. "\n")
    local cmds = " /new \194\183 /look \194\183 /lang \194\183 /help \194\183 /quit"
    local lang_tag = "[" .. current_language .. "]"
    local spacing = w - #cmds - #lang_tag
    if spacing < 1 then spacing = 1 end
    io.write(C_FOOTER .. cmds .. string.rep(" ", spacing) .. C_AMBER .. lang_tag .. RESET .. "\n")
    io.write(C_DIM .. sep .. RESET .. "\n")

    io.flush()
end

--- Build an interjection prompt for the main (randomly generated) patron.
local function build_main_interjection_prompt(c)
    local lang_rule = ""
    if current_language ~= "English" then
        lang_rule = "\nYou MUST speak entirely in " .. current_language .. "."
    end

    return string.format([[You are a patron at The Rusty Flagon, sitting at the bar.
You ARE this character — never break character, never acknowledge you are an AI.

CHARACTER SHEET:
- Name: %s
- Race: %s
- Occupation: %s
- Personality: %s
- Current state: %s (%s)
- Current mood: %s
- Speech style: %s
- Quirk: %s
- Secret: %s (don't reveal easily)

You are overhearing and participating in a conversation at the bar.

RULES:
1. Stay in character at ALL times.
2. Keep interjections SHORT — 1-2 sentences max. You're chiming in, not taking over.
3. Only speak when something catches your attention: react to something funny or dramatic, share relevant gossip, correct a wrong claim, or butt in with an opinion.
4. Show your personality and speech style.
5. Do NOT prefix your response with your name — the interface already shows who is speaking.%s]],
        c.name, c.race, c.occupation, c.personality,
        c.drunk_level, c.drunk_desc,
        c.mood, c.speech_style, c.quirk, c.secret,
        lang_rule
    )
end

-- ════════════════════════════════════════════════════════════
-- Interjection logic
-- ════════════════════════════════════════════════════════════

local MAIN_INTERJECTION_CHANCE = 0.25

--- After the primary NPC(s) respond, give other NPCs a chance to interject.
--- spoke_ids: table of NPC IDs that already responded (set-like: {["app:npc.bartender"] = true}).
--- NPCs in spoke_ids are skipped entirely.
local function try_interjections(main_char, chat_log, registry_npcs, spoke_ids)
    spoke_ids = spoke_ids or {}

    -- Registry NPCs may interject
    for _, npc in ipairs(registry_npcs) do
        if not spoke_ids[npc.id] and math.random() < npc.interjection_chance then
            render_chat(main_char, chat_log, registry_npcs, npc.name .. " chimes in...")

            local prompt = build_interjection_prompt(npc)
            local msgs = build_llm_messages(chat_log, npc.id)
            local response, err = ask_agent(prompt, msgs)

            if not err and response then
                table.insert(chat_log, {
                    speaker = npc.name,
                    kind = "npc",
                    npc_id = npc.id,
                    content = response,
                })
            end
        end
    end

    -- Main patron may interject when they didn't already speak
    if not spoke_ids["main"] and math.random() < MAIN_INTERJECTION_CHANCE then
        render_chat(main_char, chat_log, registry_npcs, main_char.name .. " chimes in...")

        local prompt = build_main_interjection_prompt(main_char)
        local msgs = build_llm_messages(chat_log, "main")
        local response, err = ask_agent(prompt, msgs)

        if not err and response then
            table.insert(chat_log, {
                speaker = main_char.name,
                kind = "npc",
                npc_id = "main",
                content = response,
            })
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- NPC lookup helper
-- ════════════════════════════════════════════════════════════

local function find_npc_by_id(registry_npcs, target_id)
    for _, npc in ipairs(registry_npcs) do
        if npc.id == target_id then
            return npc
        end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════
-- Main conversation loop
-- ════════════════════════════════════════════════════════════

local function run_conversation(registry_npcs)
    local character = generate_character()
    local system_prompt = build_main_prompt(character)

    local chat_log = {}
    table.insert(chat_log, {
        speaker = "You",
        kind = "player",
        npc_id = nil,
        content = "[You sit down at the bar next to this person.]",
    })

    render_chat(character, chat_log, registry_npcs, character.name .. " notices you...")

    -- Main NPC greeting
    local msgs = build_llm_messages(chat_log, "main")
    local greeting, err = ask_agent(system_prompt, msgs)
    if err then
        render_chat(character, chat_log, registry_npcs, "Error: " .. err)
        io.write("\n  Press Enter to try another seat...")
        io.readline()
        return false, registry_npcs
    end

    table.insert(chat_log, {
        speaker = character.name,
        kind = "npc",
        npc_id = "main",
        content = greeting,
    })

    try_interjections(character, chat_log, registry_npcs, { ["main"] = true })
    render_chat(character, chat_log, registry_npcs, nil)

    -- Interactive loop
    while true do
        io.write("  " .. C_YOU .. BOLD .. "You" .. RESET .. C_DIM .. ": " .. RESET)
        local input, read_err = io.readline()
        if read_err then
            render_chat(character, chat_log, registry_npcs, "Read error: " .. tostring(read_err))
            return false, registry_npcs
        end

        if not input then
            return false, registry_npcs
        end
        local trimmed = input:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" then
            -- Sync NPCs on empty input (just pressed Enter)
            local updated, changed = sync_npcs(registry_npcs, chat_log)
            if changed then registry_npcs = updated end
            render_chat(character, chat_log, registry_npcs, nil)
            goto continue
        end

        -- Commands
        if trimmed == "/quit" then
            render_chat(character, chat_log, registry_npcs, "You push back your stool and head for the door...")
            return true, registry_npcs
        elseif trimmed == "/new" then
            render_chat(character, chat_log, registry_npcs, "You finish your drink and move to another seat...")
            time.sleep("500ms")
            return false, registry_npcs
        elseif trimmed == "/look" then
            io.write(CLEAR .. HOME)
            io.write(C_GOLD .. BOLD .. " Who's Around" .. RESET .. "\n")
            io.write(C_DIM .. string.rep("\226\148\128", get_width()) .. RESET .. "\n\n")
            io.write("  " .. C_NPC .. BOLD .. "Talking to:" .. RESET .. "\n")
            io.write("    Name: " .. character.name .. "\n")
            io.write("    Race: " .. character.race .. "\n")
            io.write("    Looks like: " .. character.occupation .. "\n")
            io.write("    Vibe: " .. character.personality .. "\n")
            io.write("    Sobriety: " .. character.drunk_level .. "\n")
            io.write("    Seems to be: " .. character.mood .. "\n\n")
            for _, npc in ipairs(registry_npcs) do
                io.write("  " .. npc.color .. BOLD .. npc.name .. RESET .. " (" .. npc.role .. ")\n")
                io.write("    " .. (npc.data.race or "?") .. " \194\183 " .. (npc.data.occupation or "?") .. " \194\183 " .. (npc.data.drunk_level or "?") .. "\n\n")
            end
            io.write(C_DIM .. "  Press Enter to return to chat..." .. RESET)
            io.flush()
            io.readline()
            render_chat(character, chat_log, registry_npcs, nil)
            goto continue
        elseif trimmed == "/help" then
            io.write(CLEAR .. HOME)
            io.write(C_GOLD .. BOLD .. " Commands" .. RESET .. "\n")
            io.write(C_DIM .. string.rep("\226\148\128", get_width()) .. RESET .. "\n\n")
            io.write("  " .. C_YOU .. "/new" .. RESET .. "     Walk to another seat (new character)\n")
            io.write("  " .. C_YOU .. "/look" .. RESET .. "    See who's around\n")
            io.write("  " .. C_YOU .. "/lang" .. RESET .. "    Set language (e.g. /lang Spanish)\n")
            io.write("  " .. C_YOU .. "/quit" .. RESET .. "    Leave the tavern\n")
            io.write("  " .. C_YOU .. "/help" .. RESET .. "    Show this help\n\n")
            io.write("  " .. C_DIM .. "Tip: address someone by name to talk to them directly." .. RESET .. "\n")
            io.write("  " .. C_DIM .. "e.g. \"Hey bartender, give me a beer\"" .. RESET .. "\n\n")
            io.write("  Current language: " .. C_AMBER .. current_language .. RESET .. "\n\n")
            io.write(C_DIM .. "  Press Enter to return to chat..." .. RESET)
            io.flush()
            io.readline()
            render_chat(character, chat_log, registry_npcs, nil)
            goto continue
        elseif trimmed:sub(1, 5) == "/lang" then
            local lang = trimmed:match("^/lang%s+(.+)$")
            if lang then
                current_language = lang
                render_chat(character, chat_log, registry_npcs, "Language set to " .. current_language .. " (takes effect on /new)")
            else
                render_chat(character, chat_log, registry_npcs, "Current language: " .. current_language .. "  Usage: /lang <language>")
            end
            goto continue
        end

        -- Sync NPCs before processing message
        local updated, changed = sync_npcs(registry_npcs, chat_log)
        if changed then registry_npcs = updated end

        -- Add player message
        table.insert(chat_log, {
            speaker = "You",
            kind = "player",
            npc_id = nil,
            content = trimmed,
        })

        -- Ask router who should respond (returns ordered list of target IDs)
        render_chat(character, chat_log, registry_npcs, "Routing...")
        local targets = ask_router(trimmed, registry_npcs, "main", character.name, chat_log)

        -- Track who spoke as a primary responder (skip them in interjections)
        local spoke_ids = {}
        local had_error = false

        -- Generate responses for each target in order
        for _, target_id in ipairs(targets) do
            local responder_npc = find_npc_by_id(registry_npcs, target_id)

            if target_id == "main" or not responder_npc then
                -- Main patron responds
                render_chat(character, chat_log, registry_npcs, character.name .. " is thinking...")

                local llm_msgs = build_llm_messages(chat_log, "main")
                local response, gen_err = ask_agent(system_prompt, llm_msgs)

                if gen_err then
                    logger:error("generation failed for main", { error = gen_err })
                    if not had_error then
                        -- Only remove player message on first error
                        table.remove(chat_log)
                        had_error = true
                    end
                    render_chat(character, chat_log, registry_npcs, "Error: " .. gen_err)
                    goto continue
                end

                table.insert(chat_log, {
                    speaker = character.name,
                    kind = "npc",
                    npc_id = "main",
                    content = response,
                })
                spoke_ids["main"] = true

            else
                -- Registry NPC responds
                render_chat(character, chat_log, registry_npcs, responder_npc.name .. " is thinking...")

                local prompt = build_addressed_prompt(responder_npc)
                local llm_msgs = build_llm_messages(chat_log, responder_npc.id)
                local response, gen_err = ask_agent(prompt, llm_msgs)

                if gen_err then
                    logger:error("generation failed", { npc = responder_npc.name, error = gen_err })
                    -- Skip this NPC, try the next target
                else
                    table.insert(chat_log, {
                        speaker = responder_npc.name,
                        kind = "npc",
                        npc_id = responder_npc.id,
                        content = response,
                    })
                    spoke_ids[responder_npc.id] = true
                end
            end
        end

        -- Remaining NPCs may interject (skipping those who already spoke)
        if not had_error then
            try_interjections(character, chat_log, registry_npcs, spoke_ids)
        end

        render_chat(character, chat_log, registry_npcs, nil)

        ::continue::
    end
end

--- Main entry point.
local function main(): integer
    math.randomseed(math.floor(os.time()))

    local args = io.args()
    local arg_width = tonumber(args[1])
    if arg_width and arg_width > 40 then
        term_width = math.floor(arg_width)
    end

    -- Welcome screen
    io.write(CLEAR .. HOME)
    io.write("\n")
    io.write(C_GOLD .. BOLD .. "  \226\151\134 THE RUSTY FLAGON \226\151\134" .. RESET .. "\n")
    io.write(C_DIM .. "  ~ A Roguelike Bar Conversation ~" .. RESET .. "\n\n")
    io.write("  You push open the heavy oak door and step inside.\n")
    io.write("  The warm glow of lanterns, the clink of mugs, and\n")
    io.write("  a dozen conversations wash over you.\n\n")
    io.write("  Type anything to talk. " .. C_DIM .. "/help for commands." .. RESET .. "\n\n")
    io.write(C_DIM .. "  Starting up..." .. RESET)
    io.flush()

    -- Wait for services to register
    time.sleep("1s")

    -- Load persistent NPCs from registry
    local registry_npcs = load_registry_npcs()

    while true do
        local should_quit
        should_quit, registry_npcs = run_conversation(registry_npcs)
        if should_quit then
            break
        end
    end

    io.write(CLEAR .. HOME)
    io.write("\n")
    io.write(C_GOLD .. BOLD .. "  \226\151\134 THE RUSTY FLAGON \226\151\134" .. RESET .. "\n\n")
    io.write("  You step out into the cool night air.\n")
    io.write("  The sounds of the tavern fade behind you...\n\n")
    io.write("  Thanks for visiting The Rusty Flagon!\n\n")
    io.flush()

    return 0
end

return { main = main }
