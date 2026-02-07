local http = require("http")
local json = require("json")
local logger = require("logger")
local registry = require("registry")

--- Find cart process by user_id, or spawn a new one
local function find_or_spawn_cart(user_id)
    -- Try to find existing cart process
    local pid, err = process.registry.lookup("cart:" .. user_id)
    if pid then
        return pid
    end

    -- Spawn new cart process for this user
    pid, err = process.spawn("app:cart", "app:processes", user_id)
    if err then
        return nil, err
    end

    return pid
end

--- Resolve product from registry by SKU
local function find_product(sku)
    local entries, err = registry.find({ ["meta.type"] = "product" })
    if err then return nil, err end

    for _, entry in ipairs(entries) do
        if entry.data.sku == sku then
            return {
                title = entry.meta.title,
                sku = entry.data.sku,
                price = entry.data.price
            }
        end
    end

    return nil, "Product not found"
end

--- POST /api/cart/:user_id/items
--- Body: { "sku": "LAPTOP-001", "quantity": 1 }
local function handler()
    local req = http.request()
    local res = http.response()

    local user_id = req:param("user_id")
    if not user_id or #user_id == 0 then
        res:set_status(400)
        return res:write_json({ error = "user_id is required" })
    end

    local body, err = req:body_json()
    if err then
        res:set_status(400)
        return res:write_json({ error = "Invalid JSON" })
    end

    if not body.sku or type(body.sku) ~= "string" then
        res:set_status(400)
        return res:write_json({ error = "Field 'sku' is required" })
    end

    -- Look up product in registry
    local product, prod_err = find_product(body.sku)
    if not product then
        res:set_status(404)
        return res:write_json({ error = "Product not found: " .. body.sku })
    end

    -- Find or create cart process for this user
    local cart_pid, spawn_err = find_or_spawn_cart(user_id)
    if not cart_pid then
        res:set_status(500)
        return res:write_json({ error = "Failed to create cart" })
    end

    -- Send add_item message (fire-and-forget)
    process.send(cart_pid, "add_item", {
        sku = product.sku,
        title = product.title,
        price = product.price,
        quantity = body.quantity or 1
    })

    res:set_status(200)
    res:write_json({
        status = "added",
        user_id = user_id,
        item = {
            sku = product.sku,
            title = product.title,
            price = product.price,
            quantity = body.quantity or 1
        }
    })
end

return { handler = handler }
