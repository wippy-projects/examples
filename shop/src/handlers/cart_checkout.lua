local http = require("http")
local json = require("json")
local logger = require("logger")
local time = require("time")

--- POST /api/cart/:user_id/checkout
--- Tells cart process to checkout. Cart emits event and dies.
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
        res:set_status(400)
        return res:write_json({ error = "No active cart for this user" })
    end

    -- Send checkout request and wait for reply via inbox
    local inbox = process.inbox()

    process.send(cart_pid, "checkout", { reply_to = tostring(process.pid()) })

    -- Wait for reply with timeout
    local timeout = time.after("5s")
    local r = channel.select {
        inbox:case_receive(),
        timeout:case_receive()
    }

    if r.channel == timeout then
        res:set_status(504)
        return res:write_json({ error = "Checkout timed out" })
    end

    local result = r.value:payload():data()

    if not result.success then
        res:set_status(400)
        return res:write_json({ error = result.error })
    end

    res:set_status(200)
    res:write_json({
        status = "checked_out",
        order = result.order
    })
end

return { handler = handler }
