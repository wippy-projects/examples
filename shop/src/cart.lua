local logger = require("logger")
local events = require("events")
local json = require("json")

--- Cart process — one per user.
--- Maintains cart state in memory, communicates via messages.
--- On checkout: emits event to event bus, then exits.
local function main(user_id)
    local pid = process.pid()

    -- Register this process by name so HTTP handlers can find it
    local ok, err = process.registry.register("cart:" .. user_id, pid)
    if not ok then
        logger:warn("Cart already exists, exiting", { user_id = user_id, error = tostring(err) })
        return 0
    end

    local items = {}  -- { [sku] = { sku, title, price, quantity } }

    logger:info("Cart created", { pid = pid, user_id = user_id })

    local inbox = process.inbox()
    local evts = process.events()

    while true do
        local r = channel.select {
            inbox:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                logger:info("Cart shutting down", { user_id = user_id })
                process.registry.unregister("cart:" .. user_id)
                return 0
            end
        else
            local msg = r.value
            local topic = msg:topic()
            local data = msg:payload()

            if topic == "add_item" then
                local sku = data.sku
                if items[sku] then
                    items[sku].quantity = items[sku].quantity + (data.quantity or 1)
                else
                    items[sku] = {
                        sku = sku,
                        title = data.title,
                        price = data.price,
                        quantity = data.quantity or 1
                    }
                end
                logger:info("Item added", {
                    user_id = user_id,
                    sku = sku,
                    title = data.title,
                    quantity = items[sku].quantity
                })

            elseif topic == "get_cart" then
                -- Build items list and total
                local item_list = {}
                local total = 0
                for _, item in pairs(items) do
                    table.insert(item_list, item)
                    total = total + (item.price * item.quantity)
                end

                -- Reply back to the requesting process
                local reply_to = data.reply_to
                process.send(reply_to, "cart_response", {
                    user_id = user_id,
                    items = item_list,
                    total = total
                })

            elseif topic == "checkout" then
                -- Build order summary
                local item_list = {}
                local total = 0
                for _, item in pairs(items) do
                    table.insert(item_list, item)
                    total = total + (item.price * item.quantity)
                end

                if #item_list == 0 then
                    -- Reply empty cart error
                    local reply_to = data.reply_to
                    process.send(reply_to, "checkout_response", {
                        success = false,
                        error = "Cart is empty"
                    })
                else
                    local order = {
                        user_id = user_id,
                        items = item_list,
                        total = total,
                        timestamp = os.time()
                    }

                    -- Emit checkout event — delivery and notifier will pick it up
                    events.send("shop", "order.checkout", "/orders/" .. user_id, order)

                    logger:info("Checkout completed", {
                        user_id = user_id,
                        items_count = #item_list,
                        total = total
                    })

                    -- Reply success
                    local reply_to = data.reply_to
                    process.send(reply_to, "checkout_response", {
                        success = true,
                        order = order
                    })

                    -- Unregister and exit — cart is done
                    process.registry.unregister("cart:" .. user_id)
                    return 0
                end
            end
        end
    end
end

return { main = main }
