local http = require("http")
local graph_builder = require("graph_builder")

--- GET /api/graph — return DOT graph with optional filters
local function handler()
    local req = http.request()
    local res = http.response()

    local nodes, edges = graph_builder.build_graph()

    local entry_param = req:query("entry")
    local orphans_param = req:query("orphans")
    local kind_param = req:query("kind")
    local ns_param = req:query("ns")
    local depth = tonumber(req:query("depth")) or 1
    local dir = req:query("dir") or "both"

    local options = {}

    if entry_param and entry_param ~= "" then
        nodes, edges = graph_builder.focus_entry(nodes, edges, entry_param, depth, dir)
        options.focal_entry = entry_param
    elseif orphans_param == "true" then
        nodes, edges = graph_builder.find_orphans(nodes, edges)
    else
        if kind_param and kind_param ~= "" then
            nodes, edges = graph_builder.filter_by_kind(nodes, edges, kind_param)
        end
        if ns_param and ns_param ~= "" then
            nodes, edges = graph_builder.filter_by_ns(nodes, edges, ns_param)
        end
    end

    local dot = graph_builder.render_dot(nodes, edges, options)

    res:set_status(200)
    res:set_content_type("text/vnd.graphviz")
    res:write(tostring(dot))
end

return { handler = handler }
