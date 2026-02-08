local http = require("http")
local graph_builder = require("graph_builder")

--- GET /api/kinds — list unique entry kinds with counts
local function handler()
    local res = http.response()
    local kinds = graph_builder.list_kinds()
    res:set_status(200)
    res:write_json({kinds = kinds})
end

return { handler = handler }
