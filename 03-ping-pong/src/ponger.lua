local logger = require("logger")

--- Ponger service: registers itself, receives "ping", replies "pong".
--- Runs forever until the runtime shuts down.
local function main()
    local pid = process.pid()
    local inbox = process.inbox()

    process.registry.register("ponger", pid)
    logger:info("Ponger ready", { pid = tostring(pid) })

    while true do
        local msg = inbox:receive()
        local topic = msg:topic()

        if topic == "ping" then
            local data = msg:payload():data()
            local sender = tostring(msg:from())
            logger:info("Ponger received ping", { round = data.round })
            process.send(sender, "pong", { round = data.round })
        end
    end
end

return { main = main }
