local logger = require("logger")
local events = require("events")

--- Notification service — subscribes to all chat events.
--- Logs activity as a central observer. Knows nothing about rooms directly.
local function main()
    logger:info("Notification service started", { pid = process.pid() })

    local sub, err = events.subscribe("chat")
    if err then
        logger:error("Failed to subscribe", { error = tostring(err) })
        return 1
    end

    local ch = sub:channel()
    local evts = process.events()
    local total = 0

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("Notification service stopped", { events_processed = total })
                return 0
            end
        else
            local evt = r.value
            total = total + 1

            if evt.kind == "room.created" then
                logger:info("[NOTIFY] New room: #" .. evt.data.room)
            elseif evt.kind == "room.closed" then
                logger:info("[NOTIFY] Room closed: #" .. evt.data.room)
            elseif evt.kind == "user.joined" then
                logger:info("[NOTIFY] " .. evt.data.user .. " joined #" .. evt.data.room)
            elseif evt.kind == "user.left" then
                logger:info("[NOTIFY] " .. evt.data.user .. " left #" .. evt.data.room)
            elseif evt.kind == "message.sent" then
                logger:info("[NOTIFY] New message in #" .. evt.data.room .. " by " .. evt.data.user)
            end
        end
    end
end

return { main = main }
