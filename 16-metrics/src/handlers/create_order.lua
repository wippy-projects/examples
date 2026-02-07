local http = require("http")
local json = require("json")
local metrics = require("metrics")
local time = require("time")

--- POST /api/orders — create an order and record metrics.
--- Demonstrates counter, histogram, and gauge.
local function handler()
    local req = http.request()
    local res = http.response()
    local start = time.now()

    local body, err = req:body_json()
    if err or not body or not body.item then
        metrics.counter_inc("orders_total", {status = "error"})
        res:set_status(400)
        res:write_json({error = "missing 'item' field"})

        local elapsed = start:sub(time.now())
        metrics.histogram("request_duration_seconds", elapsed:seconds(), {endpoint = "create_order", status = "error"})
        return
    end

    local amount: number = tonumber(body.amount) or 1
    local price: number = tonumber(body.price) or 9.99

    -- Track order count
    metrics.counter_inc("orders_total", {status = "ok"})

    -- Track revenue
    metrics.counter_add("revenue_total", price * amount, {item = body.item})

    -- Track items sold
    metrics.counter_add("items_sold_total", amount, {item = body.item})

    -- Track pending orders gauge (simulate: increment, then decrement after "processing")
    metrics.gauge_inc("orders_pending", {})

    local order = {
        id = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)),
        item = body.item,
        amount = amount,
        price = price,
        total = price * amount
    }

    -- Simulate processing complete
    metrics.gauge_dec("orders_pending", {})

    res:set_status(201)
    res:write_json({order = order})

    -- Record request duration
    local elapsed = start:sub(time.now())
    metrics.histogram("request_duration_seconds", elapsed:seconds(), {endpoint = "create_order", status = "ok"})
end

return { handler = handler }
