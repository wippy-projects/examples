local http = require("http")
local parser = require("parser")

--- GET /api/files?lang=... — list sample source files
local function handler()
    local req = http.request()
    local res = http.response()

    local lang = req:query("lang")
    if not lang or lang == "" then
        res:set_status(400)
        res:write_json({error = "Missing 'lang' parameter"})
        return
    end

    local files, err = parser.list_files(lang)
    if err then
        res:set_status(400)
        res:write_json({error = tostring(err)})
        return
    end

    res:set_status(200)
    res:write_json({files = files, language = lang, count = #files})
end

return { handler = handler }
