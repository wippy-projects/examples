local http = require("http")
local graph_builder = require("graph_builder")

--- GET /api/rules — list active edge rules for debugging
local function handler()
    local res = http.response()
    local rules = graph_builder.list_rules()
    res:set_status(200)
    res:write_json({rules = rules, count = #rules})
end

return { handler = handler }
