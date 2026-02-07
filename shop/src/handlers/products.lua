local http = require("http")
local json = require("json")
local registry = require("registry")

--- GET /api/products — list all products from registry
local function handler()
    local req = http.request()
    local res = http.response()

    local entries, err = registry.find({ kind = "registry.entry" })
    if err then
        return res:set_status(500):write_json({ error = "Failed to query registry" })
    end

    local products = {}
    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "product" then
            table.insert(products, {
                id = entry.id,
                title = entry.meta.title,
                sku = entry.data.sku,
                price = entry.data.price,
                stock = entry.data.stock
            })
        end
    end

    res:set_status(200):write_json({ products = products })
end

return { handler = handler }
