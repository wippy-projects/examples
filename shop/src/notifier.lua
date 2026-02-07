local logger = require("logger")
local events = require("events")
local json = require("json")

--- Email notifier service — subscribes to checkout events.
--- Simulates sending order confirmation email.
local function main()
    logger:info("Email notifier started", { pid = process.pid() })

    local sub, err = events.subscribe("shop", "order.checkout")
    if err then
        logger:error("Failed to subscribe to events", { error = tostring(err) })
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
                logger:info("Email notifier shutting down")
                sub:close()
                return 0
            end
        else
            local evt = r.value
            local order = evt.data

            logger:info("================================================")
            logger:info("EMAIL: Sending order confirmation", {
                user_id = order.user_id,
                total = order.total
            })

            logger:info("EMAIL: To: " .. order.user_id .. "@example.com")
            logger:info("EMAIL: Subject: Order confirmed! Total: $" .. tostring(order.total))

            local lines = {}
            for _, item in ipairs(order.items) do
                table.insert(lines, string.format(
                    "  - %s x%d  $%.2f",
                    item.title, item.quantity, item.price * item.quantity
                ))
            end
            logger:info("EMAIL: Items:\n" .. table.concat(lines, "\n"))
            logger:info("EMAIL: Sent successfully to " .. order.user_id .. "@example.com")
            logger:info("================================================")
        end
    end
end

return { main = main }
