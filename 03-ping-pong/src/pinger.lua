local logger = require("logger")
local time = require("time")

--- Pinger service: finds ponger, sends "ping", waits for "pong", repeats.
--- Runs forever until the runtime shuts down.
local function main()
    local inbox = process.inbox()
    local round = 0

    -- Wait for ponger to register
    local ponger_pid
    while not ponger_pid do
        ponger_pid = process.registry.lookup("ponger")
        if not ponger_pid then
            time.sleep("100ms")
        end
    end

    logger:info("Pinger found ponger", { ponger = tostring(ponger_pid) })

    while true do
        round = round + 1

        process.send(ponger_pid, "ping", { round = round })
        logger:info("Pinger sent ping", { round = round })

        -- Wait for pong with timeout
        local timeout = time.after("3s")
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive()
        }

        if r.channel == timeout then
            logger:warn("Pinger timed out waiting for pong", { round = round })
        else
            local data = r.value:payload():data()
            logger:info("Pinger received pong", { round = data.round })
        end

        time.sleep("1s")
    end
end

return { main = main }
