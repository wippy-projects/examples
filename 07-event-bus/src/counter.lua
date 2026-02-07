local logger = require("logger")
local events = require("events")

--- Counter subscriber: counts events by kind.
local function main()
    logger:info("Counter started", { pid = process.pid() })

    local sub, err = events.subscribe("users")
    if err then
        logger:error("Failed to subscribe", { error = tostring(err) })
        return 1
    end

    local counts = {}
    local ch = sub:channel()
    local evts = process.events()

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("[COUNTER] Final counts", counts)
                return 0
            end
        else
            local evt = r.value
            counts[evt.kind] = (counts[evt.kind] or 0) + 1
            logger:info("[COUNTER] Running totals", counts)
        end
    end
end

return { main = main }
