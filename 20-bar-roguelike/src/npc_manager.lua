local logger = require("logger")
local registry = require("registry")
local time = require("time")
local events = require("events")

-- ════════════════════════════════════════════════════════════
-- Wandering NPC pool — characters that drift in and out
-- ════════════════════════════════════════════════════════════

local WANDERERS = {
    {
        id_suffix = "grimjaw",
        name = "Grimjaw",
        race = "half-orc",
        occupation = "bouncer on break",
        personality = "intimidating but surprisingly gentle",
        speech_style = "speaks very slowly and deliberately, pauses mid-sentence",
        quirk = "cracks knuckles before every sentence",
        secret = "writes poetry in secret",
        drunk_level = "sober",
        drunk_desc = "completely sober, always on guard",
        mood = "watching the room",
        interjection_chance = 0.15,
        entrance = "*A massive half-orc shoulders through the door, ducking under the frame. He settles onto a stool that creaks under his weight.*",
        exit = "*Grimjaw stands up slowly, nods to no one in particular, and ducks back out into the night.*",
    },
    {
        id_suffix = "old_barnaby",
        name = "Old Barnaby",
        race = "human",
        occupation = "retired sailor",
        personality = "nostalgic and long-winded",
        speech_style = "uses nautical metaphors for everything, calls drinks 'grog'",
        quirk = "squints at everything as if looking at a distant horizon",
        secret = "was actually a pirate captain but claims he was just a deckhand",
        drunk_level = "drunk",
        drunk_desc = "swaying like he's still on a ship, very talkative",
        mood = "drowning sorrows about the sea",
        interjection_chance = 0.25,
        entrance = "*An old sailor pushes through the door, bringing a whiff of salt air. He heads straight for the bar.*",
        exit = "*Old Barnaby wobbles to his feet. \"Time to weigh anchor, lads.\" He staggers toward the door.*",
    },
    {
        id_suffix = "whisper",
        name = "Whisper",
        race = "tiefling",
        occupation = "information broker",
        personality = "paranoid and conspiratorial, always glancing around",
        speech_style = "whispers everything, uses codenames for mundane things",
        quirk = "sits with back to the wall, facing the door",
        secret = "is actually selling completely made-up information",
        drunk_level = "sober",
        drunk_desc = "sharp-eyed, nursing one drink all night",
        mood = "waiting for a contact",
        interjection_chance = 0.15,
        entrance = "*A cloaked tiefling slips in through the door, barely making a sound. They find a dark corner and sit down.*",
        exit = "*Whisper stands abruptly, pulls their hood low, and vanishes through the back door.*",
    },
    {
        id_suffix = "roska",
        name = "Roska Thundermug",
        race = "dwarf",
        occupation = "competitive drinker",
        personality = "boisterous and challenge-happy",
        speech_style = "shouts everything, punctuates sentences by slamming the table",
        quirk = "lines up empty mugs in a row and counts them proudly",
        secret = "is actually a lightweight who secretly pours drinks under the table",
        drunk_level = "very drunk",
        drunk_desc = "slurring heavily, wildly emotional, thinks everyone is their best friend",
        mood = "celebrating a drinking record",
        interjection_chance = 0.3,
        entrance = "*The door SLAMS open. A stout dwarf strides in, already laughing. \"ANOTHER ROUND FOR ROSKA!\"*",
        exit = "*Roska slides off her stool. \"I'll be back... tomorrow... for the REMATCH!\" She stumbles out, knocking over a chair.*",
    },
    {
        id_suffix = "sister_vale",
        name = "Sister Vale",
        race = "human",
        occupation = "traveling healer",
        personality = "calm and nurturing but quietly judgmental",
        speech_style = "speaks softly with a serene smile, passive-aggressive observations",
        quirk = "offers unsolicited health advice about what people are drinking",
        secret = "was excommunicated from her order for a reason she won't discuss",
        drunk_level = "mildly tipsy",
        drunk_desc = "slightly loosened up, more honest than usual",
        mood = "passing through on a pilgrimage",
        interjection_chance = 0.2,
        entrance = "*A woman in simple traveling robes enters quietly. She surveys the room with a calm, appraising look before sitting down.*",
        exit = "*Sister Vale rises, smoothing her robes. \"Blessings upon this house. Try to drink more water.\" She glides out.*",
    },
    {
        id_suffix = "fang",
        name = "Fang",
        race = "goblin (reformed)",
        occupation = "rat catcher",
        personality = "nervously eager to please, desperate to fit in",
        speech_style = "talks fast, refers to self in third person sometimes",
        quirk = "keeps checking pockets as if counting something",
        secret = "still steals silverware by instinct but always returns it",
        drunk_level = "tipsy",
        drunk_desc = "giggly and oversharing",
        mood = "excited to be in a real tavern like a real person",
        interjection_chance = 0.2,
        entrance = "*A small goblin scurries in, looks around nervously, then grins wide. \"Fang is HERE! Hello, big people!\"*",
        exit = "*Fang hops off the stool. \"Fang has to go catch rats now. Bye bye, friends!\" He scampers out the door.*",
    },
}

-- ════════════════════════════════════════════════════════════
-- State
-- ════════════════════════════════════════════════════════════

-- Track which wanderers are currently in the bar (by id_suffix)
local active_wanderers = {}

-- ════════════════════════════════════════════════════════════
-- Registry operations
-- ════════════════════════════════════════════════════════════

local function add_wanderer(w)
    local entry_id = "app:wanderer." .. w.id_suffix

    local snap, err = registry.snapshot()
    if err then
        logger:error("snapshot failed", { error = tostring(err) })
        return false
    end

    local changes = snap:changes()
    changes:create({
        id = entry_id,
        kind = "registry.entry",
        meta = {
            type = "bar.npc",
            name = w.name,
            role = "wanderer",
            dynamic = "true",
        },
        data = {
            race = w.race,
            occupation = w.occupation,
            personality = w.personality,
            speech_style = w.speech_style,
            quirk = w.quirk,
            secret = w.secret,
            drunk_level = w.drunk_level,
            drunk_desc = w.drunk_desc,
            mood = w.mood,
            interjection_chance = w.interjection_chance,
            entrance = w.entrance,
            exit = w.exit,
        },
    })

    local _, apply_err = changes:apply()
    if apply_err then
        logger:error("failed to add wanderer", { name = w.name, error = tostring(apply_err) })
        return false
    end

    active_wanderers[w.id_suffix] = true
    logger:info("wanderer entered the bar", { name = w.name })
    events.send("bar.npc", "arrival", "/npcs/" .. w.id_suffix, { name = w.name, id = entry_id })
    return true
end

local function remove_wanderer(w)
    local entry_id = "app:wanderer." .. w.id_suffix

    local snap, err = registry.snapshot()
    if err then
        logger:error("snapshot failed", { error = tostring(err) })
        return false
    end

    local changes = snap:changes()
    changes:delete(entry_id)

    local _, apply_err = changes:apply()
    if apply_err then
        logger:error("failed to remove wanderer", { name = w.name, error = tostring(apply_err) })
        return false
    end

    active_wanderers[w.id_suffix] = nil
    logger:info("wanderer left the bar", { name = w.name })
    events.send("bar.npc", "departure", "/npcs/" .. w.id_suffix, { name = w.name, id = entry_id })
    return true
end

local function cleanup_all()
    for _, w in ipairs(WANDERERS) do
        if active_wanderers[w.id_suffix] then
            remove_wanderer(w)
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- NPC lifecycle
-- ════════════════════════════════════════════════════════════

local function get_available_wanderers()
    local available = {}
    for _, w in ipairs(WANDERERS) do
        if not active_wanderers[w.id_suffix] then
            table.insert(available, w)
        end
    end
    return available
end

local function get_active_wanderer_list()
    local active = {}
    for _, w in ipairs(WANDERERS) do
        if active_wanderers[w.id_suffix] then
            table.insert(active, w)
        end
    end
    return active
end

local function try_add()
    local available = get_available_wanderers()
    if #available == 0 then return end
    local w = available[math.random(1, #available)]
    add_wanderer(w)
end

local function try_remove()
    local active = get_active_wanderer_list()
    if #active == 0 then return end
    local w = active[math.random(1, #active)]
    remove_wanderer(w)
end

-- ════════════════════════════════════════════════════════════
-- Main loop
-- ════════════════════════════════════════════════════════════

local function sync_from_registry()
    local entries, err = registry.find({ kind = "registry.entry" })
    if err then return end
    local existing = {}
    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "bar.npc" and entry.meta.dynamic == "true" then
            existing[entry.id] = true
        end
    end
    for _, w in ipairs(WANDERERS) do
        local entry_id = "app:wanderer." .. w.id_suffix
        if existing[entry_id] then
            active_wanderers[w.id_suffix] = true
            logger:info("recovered existing wanderer", { name = w.name })
        end
    end
end

local function main()
    local events = process.events()
    process.registry.register("npc_manager")
    logger:info("npc manager ready")

    math.randomseed(math.floor(os.time()) + 42)

    -- Recover state from registry (handles process restarts)
    sync_from_registry()

    -- Start with one wanderer after a short delay
    local startup_delay = time.after("5s")

    local r = channel.select {
        events:case_receive(),
        startup_delay:case_receive(),
    }

    if r.channel == events then
        if r.value.kind == process.event.CANCEL then
            cleanup_all()
            process.registry.unregister("npc_manager")
            logger:info("npc manager shutting down")
            return 0
        end
    else
        try_add()
    end

    -- Main lifecycle loop
    while true do
        local delay_secs = math.random(45, 120)
        local delay = time.after(tostring(delay_secs) .. "s")

        r = channel.select {
            events:case_receive(),
            delay:case_receive(),
        }

        if r.channel == events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                cleanup_all()
                process.registry.unregister("npc_manager")
                logger:info("npc manager shutting down")
                return 0
            end
        else
            -- Timer fired: decide whether to add or remove
            local active_count = #get_active_wanderer_list()

            if active_count == 0 then
                -- Nobody here, definitely add someone
                try_add()
            elseif active_count >= 3 then
                -- Getting crowded, lean toward removing
                if math.random() < 0.7 then
                    try_remove()
                else
                    try_add()
                end
            else
                -- Normal: 60% add, 40% remove
                if math.random() < 0.6 then
                    try_add()
                else
                    try_remove()
                end
            end
        end
    end
end

return { main = main }
