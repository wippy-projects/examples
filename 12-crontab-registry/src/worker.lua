local logger = require("logger")
local time = require("time")
local funcs = require("funcs")

--- Generic cron worker: calls a function on a timer.
--- Receives entry ID and interval as spawn arguments from the scheduler.
local function main(entry_id, interval)
    logger:info("Worker started", { entry = entry_id, interval = interval, pid = process.pid() })

    local evts = process.events()
    local run = 0

    while true do
        local timer = time.after(interval)
        local r = channel.select {
            timer:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                logger:info("Worker stopped", { entry = entry_id, runs = run })
                return 0
            end
        else
            run = run + 1
            local result, err = funcs.call(entry_id)
            if err then
                logger:error("TICK FAILED", { entry = entry_id, run = run, error = tostring(err) })
            else
                logger:info("TICK", { entry = entry_id, run = run, result = result })
            end
        end
    end
end

return { main = main }
