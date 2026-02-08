local registry = require("registry")

-- ── Utility functions ───────────────────────────────────────

--- Resolve entry reference to full ID (handle relative names)
local function resolve_ref(ref, current_ns)
    if string.find(ref, ":") then
        return ref
    end
    return current_ns .. ":" .. ref
end

--- Deep get: "meta.server" → tbl.meta.server, "lifecycle.depends_on" → ...
local function deep_get(tbl, path)
    local current = tbl
    for segment in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[segment]
    end
    return current
end

--- Check if kind matches pattern ("http.endpoint" matches "http.*", "*", "http.endpoint")
local function kind_matches(kind, pattern)
    if pattern == "*" then return true end
    for alt in string.gmatch(pattern, "[^|]+") do
        if alt == kind then return true end
        local prefix = string.match(tostring(alt), "^(.+)%.%*$")
        if prefix and string.sub(kind, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

--- Filter edges to only those between existing nodes
local function filter_edges(nodes, edges)
    local filtered = {}
    for _, edge in ipairs(edges) do
        if nodes[edge.from] and nodes[edge.to] then
            table.insert(filtered, edge)
        end
    end
    return filtered
end

-- ── Rule engine ─────────────────────────────────────────────

--- Load all edge rules from registry
local function load_rules()
    local rules = {}
    local entries = registry.find({["meta.graph.rule"] = "true"})
    if entries then
        for _, entry in ipairs(entries) do
            if entry.data and entry.data.rule then
                table.insert(rules, entry.data.rule)
            end
        end
    end
    return rules
end

--- Apply a single rule to an entry, return edges
local function apply_rule(rule, entry, entry_id, ns)
    local edges = {}
    local source = rule.location == "meta" and entry.meta or entry.data

    if not source then return edges end

    -- Check optional condition
    if rule.condition then
        local actual = deep_get(entry, rule.condition.field)
        if tostring(actual) ~= rule.condition.value then
            return edges
        end
    end

    local rtype = rule.type or "field"

    if rtype == "field" then
        local value = deep_get(source, rule.field)
        if value then
            table.insert(edges, {
                from = entry_id,
                to = resolve_ref(tostring(value), ns),
                label = rule.label or rule.field,
                style = rule.edge_style or "solid",
                category = rule.category or "unknown",
            })
        end

    elseif rtype == "map_values" then
        local map = deep_get(source, rule.field)
        if type(map) == "table" then
            for key, value in pairs(map) do
                table.insert(edges, {
                    from = entry_id,
                    to = resolve_ref(tostring(value), ns),
                    label = (rule.label_prefix or "") .. key,
                    style = rule.edge_style or "solid",
                    category = rule.category or "unknown",
                })
            end
        end

    elseif rtype == "array" then
        local arr = deep_get(source, rule.field)
        if type(arr) == "table" then
            for _, value in ipairs(arr) do
                table.insert(edges, {
                    from = entry_id,
                    to = resolve_ref(tostring(value), ns),
                    label = rule.label or rule.field,
                    style = rule.edge_style or "dashed",
                    category = rule.category or "unknown",
                })
            end
        end

    elseif rtype == "array_field" then
        local arr = deep_get(source, rule.field)
        if type(arr) == "table" then
            for _, item in ipairs(arr) do
                local value = item[rule.value_field]
                if value then
                    local label = rule.label or rule.field
                    if rule.label_field and item[rule.label_field] then
                        label = tostring(item[rule.label_field])
                    end
                    table.insert(edges, {
                        from = entry_id,
                        to = resolve_ref(tostring(value), ns),
                        label = label,
                        style = rule.edge_style or "dotted",
                        category = rule.category or "unknown",
                    })
                end
            end
        end

    elseif rtype == "nested" then
        local arr = deep_get(source, rule.field)
        if type(arr) == "table" then
            for _, item in ipairs(arr) do
                for _, nested in ipairs(rule.nested_rules or {}) do
                    local sub_edges = apply_rule(nested, {data = item, meta = {}}, entry_id, ns)
                    for _, e in ipairs(sub_edges) do
                        table.insert(edges, e)
                    end
                end
            end
        end
    end

    return edges
end

-- ── Graph building ──────────────────────────────────────────

--- Build full dependency graph from registry snapshot
local function build_graph()
    local snap, snap_err = registry.snapshot()
    if snap_err then
        return {}, {}
    end

    local entries, entries_err = snap:entries()
    if entries_err or not entries then
        return {}, {}
    end

    local rules = load_rules()
    local nodes = {}
    local edges = {}

    for _, entry in ipairs(entries) do
        local id = tostring(entry.id)
        local kind = tostring(entry.kind)

        -- Skip edge rules themselves from the graph
        if not (entry.meta and entry.meta["graph.rule"] == "true") then
            local parsed = registry.parse_id(id)

            nodes[id] = {
                id = id,
                kind = kind,
                ns = parsed.ns,
                name = parsed.name,
                meta = entry.meta or {},
            }

            -- Apply all matching rules
            for _, rule in ipairs(rules) do
                if kind_matches(kind, rule.match_kind) then
                    local rule_edges = apply_rule(rule, entry, id, parsed.ns)
                    for _, edge in ipairs(rule_edges) do
                        table.insert(edges, edge)
                    end
                end
            end
        end
    end

    return nodes, edges
end

-- ── DOT rendering ───────────────────────────────────────────

local KIND_COLORS: {[string]: {fill: string, border: string}} = {
    ["http.service"]        = {fill = "#fecaca", border = "#ef4444"},
    ["http.router"]         = {fill = "#fed7aa", border = "#f97316"},
    ["http.endpoint"]       = {fill = "#fde68a", border = "#eab308"},
    ["function.lua"]        = {fill = "#bbf7d0", border = "#22c55e"},
    ["process.lua"]         = {fill = "#bfdbfe", border = "#3b82f6"},
    ["process.service"]     = {fill = "#c7d2fe", border = "#6366f1"},
    ["process.host"]        = {fill = "#ddd6fe", border = "#8b5cf6"},
    ["library.lua"]         = {fill = "#d9f99d", border = "#84cc16"},
    ["db.sql.sqlite"]       = {fill = "#e9d5ff", border = "#a855f7"},
    ["db.sql.postgres"]     = {fill = "#e9d5ff", border = "#a855f7"},
    ["store.memory"]        = {fill = "#cffafe", border = "#06b6d4"},
    ["queue.driver.memory"] = {fill = "#fbcfe8", border = "#ec4899"},
    ["queue.queue"]         = {fill = "#fce7f3", border = "#f472b6"},
    ["queue.consumer"]      = {fill = "#ffe4e6", border = "#fb7185"},
    ["template.set"]        = {fill = "#f5f5f4", border = "#a8a29e"},
    ["template.jet"]        = {fill = "#fafaf9", border = "#d6d3d1"},
    ["ns.dependency"]       = {fill = "#e0e7ff", border = "#818cf8"},
    ["workflow.lua"]        = {fill = "#fef9c3", border = "#ca8a04"},
    ["temporal.client"]     = {fill = "#fef3c7", border = "#f59e0b"},
    ["temporal.worker"]     = {fill = "#fde68a", border = "#eab308"},
    ["fs.directory"]        = {fill = "#e2e8f0", border = "#64748b"},
}

local CATEGORY_COLORS = {
    http       = "#ef4444",
    runtime    = "#3b82f6",
    queue      = "#ec4899",
    storage    = "#a855f7",
    template   = "#a8a29e",
    temporal   = "#f59e0b",
    import     = "#059669",
    lifecycle  = "#9ca3af",
    dependency = "#6366f1",
    contract   = "#14b8a6",
    views      = "#f97316",
    unknown    = "#888888",
}

--- Get color for a kind, returning default if not found
local function get_kind_colors(kind: string): (string, string)
    local c = KIND_COLORS[kind]
    if c then return c.fill, c.border end
    return "#e5e7eb", "#9ca3af"
end

--- Escape string for DOT labels
local function dot_escape(s)
    return string.gsub(s, '"', '\\"')
end

--- Render DOT with subgraph clusters by namespace
local function render_dot(nodes, edges, options)
    options = options or {}
    local lines = {}
    table.insert(lines, "digraph registry {")
    table.insert(lines, '    rankdir=LR;')
    table.insert(lines, '    node [shape=box, style="filled,rounded",')
    table.insert(lines, '          fontname="Helvetica", fontsize=11];')
    table.insert(lines, '    edge [fontname="Helvetica", fontsize=9,')
    table.insert(lines, '          color="#888888", arrowsize=0.8];')
    table.insert(lines, '')

    -- Group by namespace
    local by_ns = {}
    local ns_order = {}
    for id, node in pairs(nodes) do
        if not by_ns[node.ns] then
            by_ns[node.ns] = {}
            table.insert(ns_order, node.ns)
        end
        table.insert(by_ns[node.ns], node)
    end
    table.sort(ns_order)

    -- Subgraph cluster per namespace
    for idx, ns in ipairs(ns_order) do
        local ns_nodes = by_ns[ns]
        table.sort(ns_nodes, function(a, b) return a.id < b.id end)
        table.insert(lines, '    subgraph cluster_' .. tostring(idx - 1) .. ' {')
        table.insert(lines, '        label="' .. dot_escape(ns) .. '";')
        table.insert(lines, '        style="filled,rounded"; fillcolor="#f8f9fa"; color="#dee2e6";')
        for _, node in ipairs(ns_nodes) do
            local fill, border = get_kind_colors(tostring(node.kind))
            local label = dot_escape(node.name) .. "\\n" .. dot_escape(node.kind)
            local extra = ""
            if options.focal_entry and node.id == options.focal_entry then
                extra = ', penwidth=3'
            end
            table.insert(lines, '        "' .. dot_escape(node.id) .. '" [')
            table.insert(lines, '            label="' .. label .. '",')
            table.insert(lines, '            fillcolor="' .. fill .. '",')
            table.insert(lines, '            color="' .. border .. '"' .. extra)
            table.insert(lines, '        ];')
        end
        table.insert(lines, '    }')
    end

    -- Edges
    table.insert(lines, '')
    local seen = {}
    for _, edge in ipairs(edges) do
        if nodes[edge.from] and nodes[edge.to] then
            local key = edge.from .. "->" .. edge.to .. ":" .. edge.label
            if not seen[key] then
                seen[key] = true
                local color = CATEGORY_COLORS[edge.category] or "#888888"
                local style_attr = edge.style or "solid"
                table.insert(lines, '    "' .. dot_escape(edge.from) .. '" -> "' .. dot_escape(edge.to)
                    .. '" [label="' .. dot_escape(edge.label) .. '", color="' .. color
                    .. '", style=' .. style_attr .. '];')
            end
        end
    end

    table.insert(lines, '}')
    return table.concat(lines, "\n")
end

-- ── Filtering ───────────────────────────────────────────────

--- Filter nodes by kind pattern
local function filter_by_kind(nodes, edges, pattern)
    local filtered = {}
    for id, node in pairs(nodes) do
        if kind_matches(node.kind, pattern) then
            filtered[id] = node
        end
    end
    return filtered, filter_edges(filtered, edges)
end

--- Filter nodes by namespace (exact or prefix match)
local function filter_by_ns(nodes, edges, ns)
    local filtered = {}
    for id, node in pairs(nodes) do
        if node.ns == ns or string.sub(node.ns, 1, #ns + 1) == ns .. "." then
            filtered[id] = node
        end
    end
    return filtered, filter_edges(filtered, edges)
end

--- Focus: collect entry + neighbors up to N levels deep
local function focus_entry(nodes, edges, entry_id, depth, direction)
    depth = depth or 1
    direction = direction or "both"

    -- Build adjacency
    local out_adj = {}
    local in_adj = {}
    for _, edge in ipairs(edges) do
        if not out_adj[edge.from] then out_adj[edge.from] = {} end
        table.insert(out_adj[edge.from], edge.to)
        if not in_adj[edge.to] then in_adj[edge.to] = {} end
        table.insert(in_adj[edge.to], edge.from)
    end

    -- BFS
    local visited = {}
    local q_ids = {entry_id}
    local q_levels = {0}
    visited[entry_id] = true

    while #q_ids > 0 do
        local cur_id = table.remove(q_ids, 1)
        local cur_level: number = tonumber(table.remove(q_levels, 1)) or 0
        if cur_level < depth then
            local next_level: number = cur_level + 1
            local neighbors = {}
            if direction == "out" or direction == "both" then
                for _, n in ipairs(out_adj[cur_id] or {}) do
                    table.insert(neighbors, n)
                end
            end
            if direction == "in" or direction == "both" then
                for _, n in ipairs(in_adj[cur_id] or {}) do
                    table.insert(neighbors, n)
                end
            end
            for _, n in ipairs(neighbors) do
                if not visited[n] then
                    visited[n] = true
                    table.insert(q_ids, n)
                    table.insert(q_levels, next_level)
                end
            end
        end
    end

    local focused_nodes = {}
    for id in pairs(visited) do
        if nodes[id] then
            focused_nodes[id] = nodes[id]
        end
    end

    return focused_nodes, filter_edges(focused_nodes, edges)
end

--- Find entries with zero incoming edges
local function find_orphans(nodes, edges)
    local has_incoming = {}
    for _, edge in ipairs(edges) do
        has_incoming[edge.to] = true
    end
    local orphans = {}
    for id, node in pairs(nodes) do
        if not has_incoming[id] then
            orphans[id] = node
        end
    end
    return orphans, filter_edges(orphans, edges)
end

-- ── Analytics ───────────────────────────────────────────────

--- Find entries with most connections
local function find_hubs(nodes, edges, top_n)
    top_n = top_n or 10
    local in_counts = {} --- @type {[string]: integer}
    local out_counts = {} --- @type {[string]: integer}
    for id in pairs(nodes) do
        in_counts[id] = 0
        out_counts[id] = 0
    end
    for _, edge in ipairs(edges) do
        local oc: integer = out_counts[edge.from] or 0
        if oc >= 0 then
            out_counts[edge.from] = oc + 1
        end
        local ic: integer = in_counts[edge.to] or 0
        if ic >= 0 then
            in_counts[edge.to] = ic + 1
        end
    end
    local list = {}
    for id in pairs(nodes) do
        local ic = in_counts[id] or 0
        local oc = out_counts[id] or 0
        table.insert(list, {id = id, in_count = ic, out_count = oc, total = ic + oc})
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    local result = {}
    for i = 1, math.min(top_n, #list) do
        table.insert(result, list[i])
    end
    return result
end

--- Detect cycles using DFS
local function find_cycles(nodes, edges)
    local adj = {}
    for _, edge in ipairs(edges) do
        if not adj[edge.from] then adj[edge.from] = {} end
        table.insert(adj[edge.from], edge.to)
    end

    local WHITE, GRAY, BLACK = 0, 1, 2
    local color = {}
    for id in pairs(nodes) do
        color[id] = WHITE
    end

    local cycles = {}
    local path = {}

    local function dfs(u)
        color[u] = GRAY
        table.insert(path, u)
        for _, v in ipairs(adj[u] or {}) do
            if nodes[v] then
                if color[v] == GRAY then
                    -- Found cycle, extract it
                    local cycle = {}
                    local found = false
                    for _, p in ipairs(path) do
                        if p == v then found = true end
                        if found then table.insert(cycle, p) end
                    end
                    table.insert(cycle, v)
                    table.insert(cycles, cycle)
                elseif color[v] == WHITE then
                    dfs(v)
                end
            end
        end
        table.remove(path)
        color[u] = BLACK
    end

    for id in pairs(nodes) do
        if color[id] == WHITE then
            dfs(id)
        end
    end

    return cycles
end

--- Summary statistics
local function stats(nodes, edges)
    local node_count = 0
    local kind_counts = {}
    local ns_counts = {}
    for _, node in pairs(nodes) do
        node_count = node_count + 1
        kind_counts[node.kind] = (kind_counts[node.kind] or 0) + 1
        ns_counts[node.ns] = (ns_counts[node.ns] or 0) + 1
    end

    local has_incoming = {}
    local category_counts = {}
    for _, edge in ipairs(edges) do
        has_incoming[edge.to] = true
        category_counts[edge.category] = (category_counts[edge.category] or 0) + 1
    end

    local orphan_count = 0
    for id in pairs(nodes) do
        if not has_incoming[id] then
            orphan_count = orphan_count + 1
        end
    end

    return {
        node_count = node_count,
        edge_count = #edges,
        orphan_count = orphan_count,
        kind_counts = kind_counts,
        ns_counts = ns_counts,
        category_counts = category_counts,
    }
end

-- ── Data listing helpers ────────────────────────────────────

--- List all entries (excluding edge rules)
local function list_entries()
    local snap, err = registry.snapshot()
    if err then return {} end

    local entries, entries_err = snap:entries()
    if entries_err or not entries then return {} end

    local result = {}
    for _, entry in ipairs(entries) do
        if not (entry.meta and entry.meta["graph.rule"] == "true") then
            local parsed = registry.parse_id(tostring(entry.id))
            table.insert(result, {
                id = tostring(entry.id),
                kind = tostring(entry.kind),
                ns = parsed.ns,
                name = parsed.name,
            })
        end
    end
    return result
end

--- List unique kinds with counts
local function list_kinds()
    local entries = list_entries()
    local counts = {} --- @type {[string]: integer}
    local order = {}
    for _, e in ipairs(entries) do
        local c = counts[e.kind] or 0
        if c == 0 then
            table.insert(order, e.kind)
        end
        counts[e.kind] = c + 1
    end
    table.sort(order)
    local result = {}
    for _, kind in ipairs(order) do
        table.insert(result, {kind = kind, count = counts[kind]})
    end
    return result
end

--- List unique namespaces with counts
local function list_namespaces()
    local entries = list_entries()
    local counts = {} --- @type {[string]: integer}
    local order = {}
    for _, e in ipairs(entries) do
        local c = counts[e.ns] or 0
        if c == 0 then
            table.insert(order, e.ns)
        end
        counts[e.ns] = c + 1
    end
    table.sort(order)
    local result = {}
    for _, ns in ipairs(order) do
        table.insert(result, {ns = ns, count = counts[ns]})
    end
    return result
end

--- List active edge rules for debugging
local function list_rules()
    local rules = load_rules()
    local result = {}
    for _, rule in ipairs(rules) do
        table.insert(result, {
            match_kind = rule.match_kind,
            field = rule.field,
            type = rule.type or "field",
            location = rule.location or "data",
            category = rule.category or "unknown",
            label = rule.label or rule.label_prefix or rule.field,
            edge_style = rule.edge_style or "solid",
        })
    end
    return result
end

-- ── Full pipeline ───────────────────────────────────────────

--- Build graph and render to DOT in one call
local function build_full_dot(options)
    local nodes, edges = build_graph()
    return render_dot(nodes, edges, options)
end

-- ── Exports ─────────────────────────────────────────────────

return {
    -- Core
    build_graph = build_graph,
    render_dot = render_dot,
    build_full_dot = build_full_dot,

    -- Filtering
    filter_by_kind = filter_by_kind,
    filter_by_ns = filter_by_ns,
    focus_entry = focus_entry,
    find_orphans = find_orphans,

    -- Analytics
    find_hubs = find_hubs,
    find_cycles = find_cycles,
    stats = stats,

    -- Data helpers
    list_entries = list_entries,
    list_kinds = list_kinds,
    list_namespaces = list_namespaces,
    list_rules = list_rules,

    -- Internals (for testing)
    resolve_ref = resolve_ref,
    deep_get = deep_get,
    kind_matches = kind_matches,
    load_rules = load_rules,
    apply_rule = apply_rule,
}
