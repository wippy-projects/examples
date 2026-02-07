local treesitter = require("treesitter")
local fs = require("fs")
local registry = require("registry")

--- Tree-sitter query patterns per language
local php_queries = {
    func_defs = '(function_definition name: (name) @func_name)',
    method_defs = '(method_declaration name: (name) @method_name)',
    func_calls = '(function_call_expression function: (name) @call_name)',
    member_calls = '(member_call_expression name: (name) @member_method)',
    class_defs = '(class_declaration name: (name) @class_name)',
    class_methods = '(class_declaration name: (name) @cls (declaration_list (method_declaration name: (name) @meth)))',
}

local python_queries = {
    func_defs = '(function_definition name: (identifier) @func_name)',
    func_calls = '(call function: (identifier) @call_name)',
    attr_calls = '(call function: (attribute attribute: (identifier) @attr_name))',
    class_defs = '(class_definition name: (identifier) @class_name)',
    class_methods = '(class_definition name: (identifier) @cls body: (block (function_definition name: (identifier) @meth)))',
}

--- Resolve a language to its registry entry (volume id + file extension)
local function resolve_lang(lang: string)
    local entries = registry.find({["meta.sample_lang"] = lang})
    if not entries or #entries == 0 then
        return nil, nil, "Unknown language: " .. lang
    end
    local entry = entries[1]
    return tostring(entry.id), tostring(entry.meta.sample_ext), nil
end

--- List all registered sample languages
local function list_languages()
    local entries = registry.find({["meta.sample"] = "true"})
    local langs = {}
    if entries then
        for _, entry in ipairs(entries) do
            table.insert(langs, {
                lang = tostring(entry.meta.sample_lang),
                ext = tostring(entry.meta.sample_ext),
                label = tostring(entry.meta.sample_label),
            })
        end
    end
    return langs
end

--- Run a query and return captures, or empty table on error
local function safe_captures(lang: string, pattern: string, root: treesitter.Node, code: string)
    local query, err = treesitter.query(lang, pattern)
    if err then return {} end
    local captures = query:captures(root, code)
    if not captures then return {} end
    return captures
end

--- Walk parent nodes to find the enclosing function name
local function find_enclosing(node, lang)
    local current = node:parent()
    while current do
        local kind = current:kind()
        if lang == "php" and (kind == "function_definition" or kind == "method_declaration") then
            local n = current:child_by_field_name("name")
            if n then return tostring(n:text()) end
        elseif lang == "python" and kind == "function_definition" then
            local n = current:child_by_field_name("name")
            if n then return tostring(n:text()) end
        end
        current = current:parent()
    end
    return nil
end

--- Extract function definitions and calls from a single file
local function extract_file(lang: string, code: string, filename: string)
    local tree, err = treesitter.parse(lang, code)
    if err then return {}, {} end
    local root = tree:root_node()

    local q = lang == "php" and php_queries or python_queries

    local defs = {}
    local calls = {}

    -- Function definitions
    for _, cap in ipairs(safe_captures(lang, q.func_defs, root, code)) do
        if cap.name == "func_name" then
            defs[cap.text] = {file = filename, kind = "function"}
        end
    end

    -- Method definitions (PHP)
    if q.method_defs then
        for _, cap in ipairs(safe_captures(lang, q.method_defs, root, code)) do
            if cap.name == "method_name" then
                defs[cap.text] = {file = filename, kind = "method"}
            end
        end
    end

    -- Function calls
    for _, cap in ipairs(safe_captures(lang, q.func_calls, root, code)) do
        if cap.name == "call_name" then
            local caller = find_enclosing(cap.node, lang)
            table.insert(calls, {caller = caller, callee = cap.text})
        end
    end

    -- Member calls (PHP: $obj->method())
    if q.member_calls then
        for _, cap in ipairs(safe_captures(lang, q.member_calls, root, code)) do
            if cap.name == "member_method" then
                local caller = find_enclosing(cap.node, lang)
                table.insert(calls, {caller = caller, callee = cap.text})
            end
        end
    end

    -- Attribute calls (Python: obj.method())
    if q.attr_calls then
        for _, cap in ipairs(safe_captures(lang, q.attr_calls, root, code)) do
            if cap.name == "attr_name" then
                local caller = find_enclosing(cap.node, lang)
                table.insert(calls, {caller = caller, callee = cap.text})
            end
        end
    end

    return defs, calls
end

--- Render DOT graph from definitions and calls
local function render_dot(all_defs, all_calls)
    local lines = {}
    table.insert(lines, "digraph callgraph {")
    table.insert(lines, '    rankdir=LR;')
    table.insert(lines, '    node [shape=box, style="filled,rounded", fillcolor="#e8f4fd",')
    table.insert(lines, '          fontname="Helvetica", fontsize=11];')
    table.insert(lines, '    edge [color="#888888", arrowsize=0.8];')
    table.insert(lines, '    graph [fontname="Helvetica", fontsize=12];')
    table.insert(lines, '')

    -- Group nodes by file for subgraph clusters
    local by_file = {}
    local file_order = {}
    for name, def in pairs(all_defs) do
        if not by_file[def.file] then
            by_file[def.file] = {}
            table.insert(file_order, def.file)
        end
        table.insert(by_file[def.file], name)
    end
    table.sort(file_order)

    for idx, file in ipairs(file_order) do
        local funcs = by_file[file]
        table.sort(funcs)
        table.insert(lines, '    subgraph cluster_' .. tostring(idx - 1) .. ' {')
        table.insert(lines, '        label="' .. file .. '";')
        table.insert(lines, '        style="filled,rounded"; fillcolor="#f8f9fa";')
        table.insert(lines, '        color="#dee2e6";')
        for _, fn in ipairs(funcs) do
            local color = "#e8f4fd"
            if all_defs[fn].kind == "method" then
                color = "#d1ecf1"
            end
            table.insert(lines, '        "' .. fn .. '" [fillcolor="' .. color .. '"];')
        end
        table.insert(lines, '    }')
    end

    table.insert(lines, '')

    -- Edges: only where both caller and callee are known definitions
    local seen = {}
    for _, call in ipairs(all_calls) do
        if call.caller and all_defs[call.caller] and all_defs[call.callee] then
            local key = call.caller .. "->" .. call.callee
            if not seen[key] and call.caller ~= call.callee then
                seen[key] = true
                table.insert(lines, '    "' .. call.caller .. '" -> "' .. call.callee .. '";')
            end
        end
    end

    table.insert(lines, '}')
    return table.concat(lines, "\n")
end

--- Recursively scan source files from a volume directory
local function scan_dir(vol, dir, ext, files)
    for entry in vol:readdir(dir) do
        local path = dir == "/" and ("/" .. entry.name) or (dir .. "/" .. entry.name)
        if entry.type == "file" and string.match(entry.name, "%." .. ext .. "$") then
            -- Store relative path without leading /
            table.insert(files, string.sub(path, 2))
        elseif entry.type == "dir" or entry.type == "directory" then
            scan_dir(vol, path, ext, files)
        end
    end
end

--- Scan all source files from a volume, filtered by extension
local function scan_files(vol_id: string, ext: string)
    local vol, vol_err = fs.get(vol_id)
    if vol_err then return nil, nil, "Volume error: " .. tostring(vol_err) end

    local files = {}
    scan_dir(vol, "/", ext, files)
    table.sort(files)
    return vol, files, nil
end

--- Build the full call graph DOT for a language
local function build_call_graph(lang: string)
    local vol_id, ext, resolve_err = resolve_lang(lang)
    if resolve_err then return nil, resolve_err end

    local vol, files, scan_err = scan_files(tostring(vol_id), tostring(ext))
    if scan_err or not vol then return nil, scan_err or "Volume not found" end

    local all_defs = {}
    local all_calls = {}

    for _, filename in ipairs(files) do
        local content, read_err = vol:readfile("/" .. tostring(filename))
        if not read_err then
            local defs, calls = extract_file(lang, tostring(content), tostring(filename))
            for name, def in pairs(defs) do
                all_defs[name] = def
            end
            for _, call in ipairs(calls) do
                table.insert(all_calls, call)
            end
        end
    end

    return render_dot(all_defs, all_calls), nil
end

--- List source files for a language
local function list_files(lang: string)
    local vol_id, ext, resolve_err = resolve_lang(lang)
    if resolve_err then return nil, resolve_err end

    local _, files, scan_err = scan_files(tostring(vol_id), tostring(ext))
    if scan_err then return nil, scan_err end

    return files, nil
end

--- Read a single file from a language's volume
local function read_source(lang: string, filename: string)
    local vol_id, _, resolve_err = resolve_lang(lang)
    if resolve_err then return nil, resolve_err end

    local vol, vol_err = fs.get(tostring(vol_id))
    if vol_err then return nil, "Volume error: " .. tostring(vol_err) end

    local content, read_err = vol:readfile("/" .. tostring(filename))
    if read_err then return nil, "Read error: " .. tostring(read_err) end

    return content, nil
end

--- Build a call graph DOT for a single file
local function build_file_graph(lang: string, filename: string)
    local content, err = read_source(lang, filename)
    if err then return nil, err end

    local defs, calls = extract_file(lang, tostring(content), filename)
    return render_dot(defs, calls), nil
end

--- Extract class structure from a single file
local function extract_structure(lang, code, filename)
    local tree, err = treesitter.parse(lang, code)
    if err then return {}, {}, {} end
    local root = tree:root_node()

    local q = lang == "php" and php_queries or python_queries

    -- Collect classes and their methods
    local classes = {}
    local class_order = {}
    if q.class_methods then
        for _, cap in ipairs(safe_captures(lang, q.class_methods, root, code)) do
            if cap.name == "cls" then
                if not classes[cap.text] then
                    classes[cap.text] = {}
                    table.insert(class_order, cap.text)
                end
            elseif cap.name == "meth" then
                local cls_name = class_order[#class_order]
                if cls_name then
                    table.insert(classes[cls_name], cap.text)
                end
            end
        end
    end

    -- Collect standalone functions (not inside classes)
    local standalone = {}
    local all_methods = {}
    for _, methods in pairs(classes) do
        for _, m in ipairs(methods) do
            all_methods[m] = true
        end
    end
    for _, cap in ipairs(safe_captures(lang, q.func_defs, root, code)) do
        if cap.name == "func_name" and not all_methods[cap.text] then
            table.insert(standalone, cap.text)
        end
    end

    return classes, class_order, standalone
end

--- Render structure DOT for a single file
local function render_structure_dot(filename, classes, class_order, standalone)
    local lines = {}
    table.insert(lines, "digraph structure {")
    table.insert(lines, '    rankdir=TB;')
    table.insert(lines, '    node [fontname="Helvetica", fontsize=11];')
    table.insert(lines, '    edge [color="#888888", arrowsize=0.8];')
    table.insert(lines, '    graph [fontname="Helvetica", fontsize=12, label="' .. filename .. '", labelloc=t];')
    table.insert(lines, '')

    -- Classes as record nodes
    for _, cls in ipairs(class_order) do
        local methods = classes[cls]
        local ports = {}
        for _, m in ipairs(methods) do
            table.insert(ports, "<" .. m .. "> " .. m .. "()")
        end
        local label = "{" .. cls .. "|" .. table.concat(ports, "\\l") .. "\\l}"
        table.insert(lines, '    "' .. cls .. '" [shape=record, style="filled", fillcolor="#d1ecf1",')
        table.insert(lines, '        label="' .. label .. '"];')
    end

    -- Standalone functions
    if #standalone > 0 then
        table.insert(lines, '    subgraph cluster_functions {')
        table.insert(lines, '        label="Functions"; style="filled,rounded";')
        table.insert(lines, '        fillcolor="#f8f9fa"; color="#dee2e6";')
        for _, fn in ipairs(standalone) do
            table.insert(lines, '        "' .. fn .. '" [shape=box, style="filled,rounded", fillcolor="#e8f4fd"];')
        end
        table.insert(lines, '    }')
    end

    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

--- Build structure DOT for a single file
local function build_file_structure(lang: string, filename: string)
    local content, err = read_source(lang, filename)
    if err then return nil, err end

    local classes, class_order, standalone = extract_structure(lang, tostring(content), filename)
    return render_structure_dot(filename, classes, class_order, standalone), nil
end

--- Build external-calls DOT for a single file: shows cross-file edges
local function build_file_external(lang: string, filename: string)
    local vol_id, ext, resolve_err = resolve_lang(lang)
    if resolve_err then return nil, resolve_err end

    local vol, all_files, scan_err = scan_files(tostring(vol_id), tostring(ext))
    if scan_err or not vol then return nil, scan_err or "Volume not found" end

    -- Collect defs from ALL files, calls only from this file
    local all_defs = {}
    local all_calls = {}
    for _, f in ipairs(all_files) do
        local content, read_err = vol:readfile("/" .. tostring(f))
        if not read_err then
            local defs, calls = extract_file(lang, tostring(content), tostring(f))
            for name, def in pairs(defs) do
                all_defs[name] = def
            end
            if f == filename then
                for _, call in ipairs(calls) do
                    table.insert(all_calls, call)
                end
            end
        end
    end

    -- This file's own definitions
    local this_content, this_err = read_source(lang, filename)
    if this_err then return nil, this_err end
    local this_defs = {}
    local td, _ = extract_file(lang, tostring(this_content), filename)
    for name, def in pairs(td) do
        this_defs[name] = def
    end

    -- Collect calls FROM other files INTO this file's functions
    local incoming_calls = {}
    for _, f in ipairs(all_files) do
        if f ~= filename then
            local content, read_err = vol:readfile("/" .. tostring(f))
            if not read_err then
                local _, calls = extract_file(lang, tostring(content), tostring(f))
                for _, call in ipairs(calls) do
                    if call.caller and this_defs[call.callee] and all_defs[call.caller] then
                        table.insert(incoming_calls, {caller = call.caller, callee = call.callee, file = f})
                    end
                end
            end
        end
    end

    -- Build DOT
    local lines = {}
    table.insert(lines, "digraph external {")
    table.insert(lines, '    rankdir=LR;')
    table.insert(lines, '    node [shape=box, style="filled,rounded", fontname="Helvetica", fontsize=11];')
    table.insert(lines, '    edge [fontname="Helvetica", fontsize=9];')
    table.insert(lines, '    graph [fontname="Helvetica", fontsize=12];')
    table.insert(lines, '')

    -- This file's functions (center cluster)
    table.insert(lines, '    subgraph cluster_this {')
    table.insert(lines, '        label="' .. filename .. '";')
    table.insert(lines, '        style="filled,rounded"; fillcolor="#dbeafe"; color="#93c5fd";')
    for name, _ in pairs(this_defs) do
        table.insert(lines, '        "' .. name .. '" [fillcolor="#bfdbfe"];')
    end
    table.insert(lines, '    }')

    -- Outgoing calls
    local ext_targets = {}
    local seen_out = {}
    for _, call in ipairs(all_calls) do
        if call.caller and this_defs[call.caller] and all_defs[call.callee]
           and not this_defs[call.callee] then
            local key = call.caller .. "->" .. call.callee
            if not seen_out[key] then
                seen_out[key] = true
                local target_file = all_defs[call.callee].file
                if not ext_targets[target_file] then
                    ext_targets[target_file] = {}
                end
                ext_targets[target_file][call.callee] = true
                table.insert(lines, '    "' .. call.caller .. '" -> "' .. call.callee
                    .. '" [color="#4f46e5", label="calls"];')
            end
        end
    end

    -- Incoming calls
    local ext_sources = {}
    local seen_in = {}
    for _, call in ipairs(incoming_calls) do
        local key = call.caller .. "->" .. call.callee
        if not seen_in[key] then
            seen_in[key] = true
            if not ext_sources[call.file] then
                ext_sources[call.file] = {}
            end
            ext_sources[call.file][call.caller] = true
            table.insert(lines, '    "' .. call.caller .. '" -> "' .. call.callee
                .. '" [color="#059669", label="calls"];')
        end
    end

    -- External file clusters (outgoing targets)
    local cluster_idx = 1
    for file, funcs in pairs(ext_targets) do
        table.insert(lines, '    subgraph cluster_ext_' .. tostring(cluster_idx) .. ' {')
        table.insert(lines, '        label="' .. file .. '";')
        table.insert(lines, '        style="filled,rounded"; fillcolor="#fef3c7"; color="#fbbf24";')
        for fn, _ in pairs(funcs) do
            table.insert(lines, '        "' .. fn .. '" [fillcolor="#fde68a"];')
        end
        table.insert(lines, '    }')
        cluster_idx = cluster_idx + 1
    end

    -- External file clusters (incoming sources)
    for file, funcs in pairs(ext_sources) do
        if not ext_targets[file] then
            table.insert(lines, '    subgraph cluster_ext_' .. tostring(cluster_idx) .. ' {')
            table.insert(lines, '        label="' .. file .. '";')
            table.insert(lines, '        style="filled,rounded"; fillcolor="#d1fae5"; color="#34d399";')
            for fn, _ in pairs(funcs) do
                table.insert(lines, '        "' .. fn .. '" [fillcolor="#a7f3d0"];')
            end
            table.insert(lines, '    }')
            cluster_idx = cluster_idx + 1
        end
    end

    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

return {
    list_languages = list_languages,
    list_files = list_files,
    build_call_graph = build_call_graph,
    build_file_graph = build_file_graph,
    build_file_structure = build_file_structure,
    build_file_external = build_file_external,
}
