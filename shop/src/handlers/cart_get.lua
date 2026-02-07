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
        return res:set_status(400):write_json({ error = "user_id is required" })
    end

    -- Look up cart process
    local cart_pid, err = process.registry.lookup("cart:" .. user_id)
    if not cart_pid then
        return res:set_status(200):write_json({
            user_id = user_id,
            items = {},
            total = 0,
            message = "Cart is empty (no active session)"
        })
    end

    -- Subscribe to reply topic, send request, wait for response
    local reply_ch = process.listen("cart_response")

    process.send(cart_pid, "get_cart", { reply_to = process.pid() })

    -- Wait for reply with timeout
    local timeout = time.after("3s")
    local r = channel.select {
        reply_ch:case_receive(),
        timeout:case_receive()
    }
    process.unlisten(reply_ch)

    if r.channel == timeout then
        return res:set_status(504):write_json({ error = "Cart process did not respond" })
    end

    local cart = r.value:payload()

    res:set_status(200):write_json(cart)
end

return { handler = handler }
