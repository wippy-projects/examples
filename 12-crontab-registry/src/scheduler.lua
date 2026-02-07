local logger = require("logger")
local time = require("time")
local registry = require("registry")

--- Scheduler: discovers cron.job functions from registry, spawns a worker for each.
--- Adding a new job = adding a function.lua entry with meta.type: cron.job.
---
--- Run: wippy run
local function main()
    logger:info("Scheduler started", { pid = process.pid() })

    -- Discover all job functions from registry
    local entries, err = registry.find({ ["meta.type"] = "cron.job" })
    if err then
        logger:error("Failed to find jobs", { error = tostring(err) })
        return 1
    end

    logger:info("Discovered jobs", { count = #entries })

    -- Spawn a worker process for each job function
    for _, entry in ipairs(entries) do
        local interval = entry.meta.interval
        logger:info("Spawning worker", { entry = entry.id, interval = interval })
        process.spawn("app:worker", "app:processes", entry.id, interval)
    end

    -- Wait for shutdown
    local evts = process.events()
    while true do
        local r = channel.select {
            evts:case_receive()
        }
        if r.value.kind == process.event.CANCEL then
            logger:info("Scheduler stopping")
            return 0
        end
    end
end

return { main = main }
