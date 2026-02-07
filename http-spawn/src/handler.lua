local http = require("http")
local json = require("json")
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
        return res:write_json({ error = "Field 'name' is required" })
    end

    local task = {
        name = body.name,
        duration = body.duration or 3
    }

    -- Spawn a dedicated process for this task.
    -- Each task gets its own isolated actor with private state.
    -- The process runs, does its work, and exits — freeing memory.
    local pid = process.spawn("app:task_worker", "app:processes", task)

    logger:info("Task process spawned", { pid = pid, name = task.name })

    -- Respond immediately — the process works in the background
    res:set_status(202)
    res:write_json({
        pid = pid,
        name = task.name,
        status = "spawned",
        message = string.format("Process %s will run for %d seconds", pid, task.duration)
    })
end

return { handler = handler }
