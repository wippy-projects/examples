local logger = require("logger")
local time = require("time")

--- Task worker process.
--- Receives task data as argument, executes the work step by step,
--- then exits cleanly (return 0). The process dies, memory is freed.
--- Each task = its own isolated actor. No shared state.
local function main(task)
    local pid = process.pid()
    local name = task.name or "unknown"
    local duration = task.duration or 3

    logger:info("Worker started", { pid = pid, task = name, steps = duration })

    -- Simulate work in steps
    for step = 1, duration do
        time.sleep("1s")
        logger:info("Worker progress", {
            pid = pid,
            task = name,
            step = step,
            total = duration
        })
    end

    logger:info("Worker done, exiting", { pid = pid, task = name })

    -- Return 0 = clean exit. Process dies, memory freed.
    -- Supervisor will NOT restart it (normal exit).
    return 0
end

return { main = main }
