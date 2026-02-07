local time = require("time")
local logger = require("logger")

--- Worker: runs in a while loop, ticks periodically and logs to stdout.
--- Each worker is a separate lightweight process (~13KB overhead).
---
--- Spawned by the spawner with:
---   process.spawn_monitored("app:worker", "app:processes", spawner_pid, id, tick_interval)
local function main(spawner_pid: string, worker_id: integer, tick_interval: string)
    local events = process.events()
    local ticker = time.ticker(tick_interval)
    local tick_ch = ticker:response()
    local tick_count = 0

    logger:debug("worker started", {
        worker_id = worker_id,
        tick_interval = tick_interval,
    })

    while true do
        local r = channel.select {
            events:case_receive(),
            tick_ch:case_receive()
        }

        if r.channel == events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                ticker:stop()
                logger:debug("worker stopped", {
                    worker_id = worker_id,
                    ticks = tick_count,
                })
                process.send(spawner_pid, "stopped", {
                    id = worker_id,
                    ticks = tick_count,
                })
                return 0
            end

        elseif r.channel == tick_ch then
            tick_count = tick_count + 1
            logger:debug("tick", {
                worker_id = worker_id,
                tick = tick_count,
            })
            process.send(spawner_pid, "tick", {
                id = worker_id,
                tick = tick_count,
            })
        end
    end
end

return { main = main }
