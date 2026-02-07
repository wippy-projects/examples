local logger = require("logger")
local registry = require("registry")
local llm = require("llm")

-- ════════════════════════════════════════════════════════════
-- Registry NPC loading
-- ════════════════════════════════════════════════════════════

--- Load all bar NPCs from the registry.
local function load_npcs()
    local entries, err = registry.find({ kind = "registry.entry" })
    if err then
        logger:error("registry.find failed", { error = tostring(err) })
        return {}
    end

    local npcs = {}
    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "bar.npc" then
            local d = entry.data or {}
            table.insert(npcs, {
                id = entry.id,
                name = entry.meta.name or "Unknown",
                role = entry.meta.role or "regular",
                personality = d.personality or "",
                drunk_level = d.drunk_level or "sober",
                mood = d.mood or "",
                occupation = d.occupation or "",
            })
        end
    end
    return npcs
end

-- ════════════════════════════════════════════════════════════
-- Schema: LLM returns an ordered list of responders
-- ════════════════════════════════════════════════════════════

local ROUTE_SCHEMA = {
    type = "object",
    properties = {
        responders = {
            type = "array",
            description = "Ordered list of NPCs who should respond, from most relevant to least. "
                .. "1 entry for direct address, 2-3 for group/open messages.",
            items = {
                type = "object",
                properties = {
                    target_id = {
                        type = "string",
                        description = "The EXACT ID string from the list. Copy it verbatim.",
                    },
                    reason = {
                        type = "string",
                        description = "Brief reason this NPC would respond (e.g. 'directly addressed', "
                            .. "'would react to this topic', 'bartender duty', 'continuing conversation').",
                    },
                },
                required = { "target_id", "reason" },
            },
            minItems = 1,
            maxItems = 4,
        },
    },
    required = { "responders" },
}

-- ════════════════════════════════════════════════════════════
-- Prompt builder
-- ════════════════════════════════════════════════════════════

local function build_route_prompt(text, npcs, main_npc_id, main_name, context)
    local lines = {
        "You are a message router for a fantasy tavern conversation game.",
        "Decide which NPC(s) the player is talking to and who would naturally respond.",
        "",
        "ROUTING RULES:",
        "- If the player addresses someone BY NAME → return ONLY that person.",
        "- If the message is a short reply or continuation (e.g. 'yes', 'sure', 'beer please', 'tell me more') →",
        "  look at the RECENT CONVERSATION to see who the player was just talking to. Route to THAT person.",
        "- If the message is about ordering drinks/food without naming anyone → route to the bartender.",
        "- If the message is directed at the room, everyone, or is a general question/statement →",
        "  pick 2-3 NPCs who would MOST NATURALLY respond based on their personality, mood, and role.",
        "- Order matters: the first responder speaks first.",
        "- Return the EXACT ID strings from the list below. Copy them verbatim.",
        "",
        "People in the tavern (ID — Name — Details):",
        "  ID: \"" .. main_npc_id .. "\" — " .. main_name .. " (the patron the player is sitting next to)",
    }
    for _, npc in ipairs(npcs) do
        local parts = { npc.name }
        if npc.role ~= "regular" and npc.role ~= "wanderer" then
            table.insert(parts, npc.role)
        end
        if npc.personality ~= "" then
            table.insert(parts, npc.personality)
        end
        if npc.drunk_level ~= "sober" then
            table.insert(parts, npc.drunk_level)
        end
        table.insert(lines, "  ID: \"" .. npc.id .. "\" — " .. table.concat(parts, ", "))
    end
    table.insert(lines, "")
    table.insert(lines, "Default (if unsure or nobody specific): \"" .. main_npc_id .. "\"")

    -- Add conversation context if available
    if context and context ~= "" then
        table.insert(lines, "")
        table.insert(lines, "RECENT CONVERSATION (use this to determine who the player is replying to):")
        table.insert(lines, context)
    end

    table.insert(lines, "")
    table.insert(lines, 'Player\'s NEW message: "' .. text .. '"')
    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════
-- Fuzzy matching
-- ════════════════════════════════════════════════════════════

local function fuzzy_match_npc(answer, npcs, main_npc_id, main_name)
    if not answer or answer == "" then
        return nil
    end

    local lower = answer:lower()

    -- Check main patron
    if main_name then
        local lower_main = main_name:lower()
        if lower_main:find(lower, 1, true) or lower:find(lower_main, 1, true) then
            return main_npc_id
        end
    end

    -- Check registry NPCs by name, role, or ID substring
    for _, npc in ipairs(npcs) do
        local lower_name = (npc.name or ""):lower()
        local lower_id = (npc.id or ""):lower()
        local lower_role = (npc.role or ""):lower()

        if lower_name:find(lower, 1, true) or lower:find(lower_name, 1, true) then
            return npc.id
        end
        if lower_id:find(lower, 1, true) or lower:find(lower_id, 1, true) then
            return npc.id
        end
        if lower_role ~= "" and (lower_role:find(lower, 1, true) or lower:find(lower_role, 1, true)) then
            return npc.id
        end
    end

    return nil
end

local function resolve_one(raw_id, npcs, main_npc_id, main_name)
    if raw_id == main_npc_id then
        return main_npc_id
    end
    for _, npc in ipairs(npcs) do
        if raw_id == npc.id then
            return npc.id
        end
    end
    return fuzzy_match_npc(raw_id, npcs, main_npc_id, main_name)
end

-- ════════════════════════════════════════════════════════════
-- Main resolution
-- ════════════════════════════════════════════════════════════

local function resolve_targets(text, npcs, main_npc_id, main_name, context)
    local full_prompt = build_route_prompt(text, npcs, main_npc_id, main_name, context)

    logger:info("routing request", { text = text })

    local result, err = llm.structured_output(ROUTE_SCHEMA, full_prompt, {
        model = "class:fast",
    })

    if err then
        logger:error("LLM routing error", { error = tostring(err) })
        return { main_npc_id }
    end

    if not result or not result.result then
        logger:warn("LLM routing: empty result")
        return { main_npc_id }
    end

    local responders = result.result.responders
    if not responders or type(responders) ~= "table" or #responders == 0 then
        -- Backwards compat: maybe LLM returned old single-target format
        if result.result.target_id then
            local resolved = resolve_one(result.result.target_id, npcs, main_npc_id, main_name)
            return { resolved or main_npc_id }
        end
        logger:warn("LLM routing: no responders in result")
        return { main_npc_id }
    end

    -- Resolve each responder, deduplicate, preserve order
    local targets = {}
    local seen = {}
    for _, entry in ipairs(responders) do
        local raw_id = entry.target_id or ""
        local reason = entry.reason or ""
        local resolved = resolve_one(raw_id, npcs, main_npc_id, main_name)

        if resolved and not seen[resolved] then
            seen[resolved] = true
            table.insert(targets, resolved)
            logger:info("route target resolved", {
                raw = raw_id,
                resolved = resolved,
                reason = reason,
            })
        elseif not resolved then
            logger:warn("LLM returned unresolvable ID, skipping", { raw = raw_id })
        end
    end

    if #targets == 0 then
        return { main_npc_id }
    end

    return targets
end

-- ════════════════════════════════════════════════════════════
-- Process main loop
-- ════════════════════════════════════════════════════════════

local function main()
    local events = process.events()
    local inbox = process.inbox()

    process.registry.register("router")
    logger:info("router ready")

    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
        }

        if r.channel == events then
            if r.value.kind == process.event.CANCEL then
                process.registry.unregister("router")
                logger:info("router shutting down")
                return 0
            end

        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()
            local data = msg:payload():data()
            local sender = msg:from()

            if topic == "route" then
                local text = data.text or ""
                local main_npc_id = data.main_npc_id or "main"
                local main_name = data.main_name or "the patron"
                local context = data.context or ""

                -- Load NPCs fresh from registry (picks up wanderer changes)
                local npcs = load_npcs()

                logger:info("route request received", {
                    text = text,
                    sender = tostring(sender),
                    npc_count = #npcs,
                })

                local targets = resolve_targets(text, npcs, main_npc_id, main_name, context)

                logger:info("sending route result", { targets = targets })
                process.send(sender, "route_result", {
                    targets = targets,
                    target_id = targets[1],
                })
            end
        end
    end
end

return { main = main }
