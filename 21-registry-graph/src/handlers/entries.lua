local http = require("http")
local graph_builder = require("graph_builder")

--- GET /api/entries — list all registry entries (excluding edge rules)
local function handler()
    local res = http.response()
    local entries = graph_builder.list_entries()
    res:set_status(200)
    res:write_json({entries = entries, count = #entries})
end

return { handler = handler }
