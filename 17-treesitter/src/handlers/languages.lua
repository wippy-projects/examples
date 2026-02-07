local http = require("http")
local parser = require("parser")

--- GET /api/languages — list registered sample languages
local function handler()
    local res = http.response()
    local langs = parser.list_languages()
    res:set_status(200)
    res:write_json({languages = langs})
end

return { handler = handler }
