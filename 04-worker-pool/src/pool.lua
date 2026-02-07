local io = require("io")
local time = require("time")

type Job = {id: integer, input: integer}
type Result = {job_id: integer, worker: integer, value: integer}

--- Worker pool using channels and coroutines.
--- Demonstrates fan-out (distribute work) and fan-in (collect results).
--- All within a single process — channels coordinate coroutines.
---
--- Run: wippy run -x app:pool
local function main(): integer
    io.print("=== Worker Pool: Channels + Coroutines ===")
    io.print("")

    local num_workers = 3
    local num_jobs = 10

    local jobs = channel.new(num_jobs)
    local results = channel.new(num_jobs)

    -- Spawn worker coroutines
    for w = 1, num_workers do
        coroutine.spawn(function()
            while true do
                local job, ok = jobs:receive()
                if not ok then break end -- channel closed

                -- Simulate work
                time.sleep("200ms")
                local result = {
                    job_id = job.id,
                    worker = w,
                    value = job.input * job.input -- square the number
                }
                results:send(result)
            end
        end)
    end

    io.print("Spawned " .. num_workers .. " workers")
    io.print("Sending " .. num_jobs .. " jobs...")
    io.print("")

    -- Send all jobs
    for i = 1, num_jobs do
        jobs:send({ id = i, input = i })
    end
    jobs:close() -- signal no more work

    -- Collect all results
    for i = 1, num_jobs do
        local r, ok = results:receive()
        if not ok then break end
        io.print(string.format(
            "  Job #%d: %d^2 = %d  (worker %d)",
            r.job_id, r.job_id, r.value, r.worker
        ))
    end

    io.print("")
    io.print("All jobs done. Workers shared a channel, no shared state.")
    return 0
end

return { main = main }
