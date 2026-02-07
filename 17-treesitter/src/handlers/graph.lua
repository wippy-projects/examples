local http = require("http")
local parser = require("parser")

--- GET /api/graph?lang=php|python — return DOT call graph
local function handler()
    local req = http.request()
    local res = http.response()

    local lang = req:query("lang")
    if not lang or lang == "" then
        res:set_status(400)
        res:set_content_type("text/plain")
        res:write("Missing 'lang' parameter")
        return
    end

    local file = req:query("file")
    local gtype = req:query("type")
    local dot, err
    if file and file ~= "" then
        if gtype == "structure" then
            dot, err = parser.build_file_structure(lang, file)
        elseif gtype == "external" then
            dot, err = parser.build_file_external(lang, file)
        else
            dot, err = parser.build_file_graph(lang, file)
        end
    else
        dot, err = parser.build_call_graph(lang)
    end
    if err then
        res:set_status(500)
        res:set_content_type("text/plain")
        res:write("Error: " .. err)
        return
    end

    res:set_status(200)
    res:set_content_type("text/vnd.graphviz")
    res:write(tostring(dot))
end

return { handler = handler }
