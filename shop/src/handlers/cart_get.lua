local http = require("http")
local json = require("json")
local logger = require("logger")
local time = require("time")

--- GET /api/cart/:user_id
--- Sends message to cart process, waits for reply
local function handler()
    local req = http.request()
    local res = http.response()

    local user_id = req:param("user_id")
    if not user_id or #user_id == 0 then
        res:set_status(400)
        return res:write_json({ error = "user_id is required" })
    end

    -- Look up cart process
    local cart_pid, err = process.registry.lookup("cart:" .. user_id)
    if not cart_pid then
        res:set_status(200)
        return res:write_json({
            user_id = user_id,
            items = {},
            total = 0,
            message = "Cart is empty (no active session)"
        })
    end

    -- Send request and wait for reply via inbox
    local inbox = process.inbox()

    process.send(cart_pid, "get_cart", { reply_to = tostring(process.pid()) })

    -- Wait for reply with timeout
    local timeout = time.after("3s")
    local r = channel.select {
        inbox:case_receive(),
        timeout:case_receive()
    }

    if r.channel == timeout then
        res:set_status(504)
        return res:write_json({ error = "Cart process did not respond" })
    end

    local cart = r.value:payload():data()

    res:set_status(200)
    res:write_json(cart)
end

return { handler = handler }
