local logger = require("logger")
local events = require("events")

--- Audit log subscriber: logs every event from "users" system.
local function main()
    logger:info("Audit log started", { pid = process.pid() })

    local sub, err = events.subscribe("users")
    if err then
        logger:error("Failed to subscribe", { error = tostring(err) })
        return 1
    end

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
                return 0
            end
        else
            local evt = r.value
            logger:info("[AUDIT] " .. evt.kind, {
                path = evt.path,
                data = evt.data
            })
        end
    end
end

return { main = main }
