local http = require("http")
local json = require("json")
local registry = require("registry")

--- GET /api/products — list all products from registry
local function handler()
    local req = http.request()
    local res = http.response()

    local entries, err = registry.find({ ["meta.type"] = "product" })
    if err then
        res:set_status(500)
        return res:write_json({ error = "Failed to query registry" })
    end

    local products = {}
    for _, entry in ipairs(entries) do
        table.insert(products, {
            id = entry.id,
            title = entry.meta.title,
            sku = entry.data.sku,
            price = entry.data.price,
            stock = entry.data.stock
        })
    end

    res:set_status(200)
    res:write_json({ products = products })
end

return { handler = handler }
