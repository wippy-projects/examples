local http = require("http")
local graph_builder = require("graph_builder")

--- GET /api/namespaces — list unique namespaces with counts
local function handler()
    local res = http.response()
    local namespaces = graph_builder.list_namespaces()
    res:set_status(200)
    res:write_json({namespaces = namespaces})
end

return { handler = handler }
