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
        return res:set_status(400):write_json({ error = "user_id is required" })
    end

    -- Look up cart process
    local cart_pid, err = process.registry.lookup("cart:" .. user_id)
    if not cart_pid then
        return res:set_status(400):write_json({ error = "No active cart for this user" })
    end

    -- Subscribe to reply topic, send checkout request, wait for response
    local reply_ch = process.listen("checkout_response")

    process.send(cart_pid, "checkout", { reply_to = process.pid() })

    -- Wait for reply with timeout
    local timeout = time.after("5s")
    local r = channel.select {
        reply_ch:case_receive(),
        timeout:case_receive()
    }
    process.unlisten(reply_ch)

    if r.channel == timeout then
        return res:set_status(504):write_json({ error = "Checkout timed out" })
    end

    local result = r.value:payload()

    if not result.success then
        return res:set_status(400):write_json({ error = result.error })
    end

    res:set_status(200):write_json({
        status = "checked_out",
        order = result.order
    })
end

return { handler = handler }
