local http = require("http")
local json = require("json")
local time = require("time")
local logger = require("logger")

local function handler()
    local req = http.request()
    local res = http.response()

    local body, err = req:body_json()
    if err then
        res:set_status(400)
        return res:write_json({ error = "Invalid JSON" })
    end

    if not body.name or type(body.name) ~= "string" or #body.name == 0 then
        res:set_status(400)
        return res:write_json({ error = "Field 'name' is required (non-empty string)" })
    end

    local task = body

    local task_id = string.format("task_%d", os.time())
    local duration = task.duration or 3

    -- Spawn a coroutine to process the task in the background.
    -- The coroutine runs concurrently within the same process,
    -- so the HTTP response returns immediately.
    coroutine.spawn(function()
        logger:info("Task started", { task_id = task_id, name = task.name })

        -- Simulate work in steps
        for step = 1, duration do
            time.sleep("1s")
            logger:info("Task progress", {
                task_id = task_id,
                step = step,
                total = duration
            })
        end

        logger:info("Task completed", { task_id = task_id, name = task.name })
    end)

    -- Respond immediately — the coroutine continues in the background
    res:set_status(202)
    res:write_json({
        task_id = task_id,
        name = task.name,
        status = "accepted",
        message = string.format("Task will run for %d seconds in background", duration)
    })
end

return { handler = handler }
