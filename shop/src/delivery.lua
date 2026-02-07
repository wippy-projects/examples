local logger = require("logger")
local events = require("events")
local json = require("json")

--- Delivery service — subscribes to checkout events.
--- Simulates scheduling a delivery for each order.
local function main()
    logger:info("Delivery service started", { pid = process.pid() })

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
                logger:info("Delivery service shutting down")
                sub:close()
                return 0
            end
        else
            local evt = r.value
            local order = evt.data

            logger:info("================================================")
            logger:info("DELIVERY: Scheduling delivery", {
                user_id = order.user_id,
                items_count = #order.items,
                total = order.total
            })

            for _, item in ipairs(order.items) do
                logger:info("DELIVERY: Packing item", {
                    sku = item.sku,
                    title = item.title,
                    quantity = item.quantity
                })
            end

            logger:info("DELIVERY: Package dispatched for user " .. order.user_id)
            logger:info("================================================")
        end
    end
end

return { main = main }
