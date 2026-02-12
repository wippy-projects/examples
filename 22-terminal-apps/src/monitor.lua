--- System Monitor — real-time dashboard using the Elm Architecture.
---
--- Demonstrates: app runtime with tick, table_view, progress, spinner,
--- tabs, help, style, layout, theme, border, and the system module.
---
--- Controls:
---   ←/→           switch tab (Overview / Services / Memory)
---   1 / 2 / 3     jump to tab
---   ↑/↓ or j/k   navigate service table
---   ?             toggle full help
---   q             quit

local app        = require("app")
local style      = require("style")
local tabs_mod   = require("tabs")
local table_view = require("table_view")
local progress   = require("progress")
local spinner    = require("spinner")
local help       = require("help")
local layout     = require("layout")
local theme      = require("theme")
local time       = require("time")
local collector  = require("collector")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local CONTENT_HEIGHT = 16

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function format_bytes(n)
    if n >= 1073741824 then
        return string.format("%.1f GB", n / 1073741824)
    elseif n >= 1048576 then
        return string.format("%.1f MB", n / 1048576)
    elseif n >= 1024 then
        return string.format("%.1f KB", n / 1024)
    end
    return string.format("%d B", n)
end

local function format_number(n)
    local s = tostring(math.floor(n))
    local result = ""
    local len = #s
    for i = 1, len do
        result = result .. s:sub(i, i)
        local remaining = len - i
        if remaining > 0 and remaining % 3 == 0 then
            result = result .. ","
        end
    end
    return result
end

local function format_uptime(started_at_ns)
    if not started_at_ns or started_at_ns == 0 then return "-" end
    local now_ns = time.now():unix_nano()
    local elapsed_secs = math.floor((now_ns - started_at_ns) / 1e9)
    if elapsed_secs <= 0 then return "0s" end
    local mins = math.floor(elapsed_secs / 60)
    local secs = elapsed_secs % 60
    if mins >= 60 then
        local hrs = math.floor(mins / 60)
        mins = mins % 60
        return string.format("%dh %dm", hrs, mins)
    end
    if mins > 0 then
        return string.format("%dm %ds", mins, secs)
    end
    return string.format("%ds", secs)
end

--- Pad content to exactly CONTENT_HEIGHT lines.
local function pad_content(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    while #lines < CONTENT_HEIGHT do
        table.insert(lines, "")
    end
    -- Truncate if too many lines
    while #lines > CONTENT_HEIGHT do
        table.remove(lines)
    end
    return table.concat(lines, "\n")
end

--- Collect all system data into the model using the collector library.
local function collect_data(model)
    local stats = collector.collect_stats()

    if stats.hostname then model.hostname = stats.hostname end
    if stats.pid then model.pid = stats.pid end
    if stats.cpu_count then model.cpu_count = stats.cpu_count end
    if stats.max_procs then model.max_procs = stats.max_procs end
    if stats.goroutines then model.goroutines = stats.goroutines end
    if stats.mem_stats then model.mem_stats = stats.mem_stats end
    if stats.services then model.services = stats.services end
    if stats.modules then model.modules = stats.modules end
    if stats.total_entries then model.total_entries = stats.total_entries end
    if stats.entry_counts then model.entry_counts = stats.entry_counts end

    -- Update service table rows (enrich with registry entry details)
    if model.services then
        local details = stats.entry_details or {}
        local rows = {}
        for i = 1, #model.services do
            local svc = model.services[i]
            local svc_id = svc.id or ""

            -- Look up entry info from collected details
            local kind = ""
            local detail = ""
            local entry_info = details[svc_id]
            if entry_info then
                kind = entry_info.kind or ""
                local meta = entry_info.meta or {}

                -- Try to find pool config
                local pool = meta.pool
                if pool then
                    local pt = pool.type or "auto"
                    if pool.workers then
                        detail = pt .. " w:" .. pool.workers
                    elseif pool.max_size then
                        detail = pt .. " max:" .. pool.max_size
                    else
                        detail = pt
                    end
                end

                -- Show smart defaults based on entry kind
                if detail == "" then
                    if kind == "process.host" then
                        detail = "w:" .. model.cpu_count .. " q:1024"
                    elseif kind == "terminal.host" then
                        detail = "terminal I/O"
                    elseif kind == "process.service" then
                        local proc = meta.process or ""
                        detail = tostring(proc):gsub("^%w+:", "")
                    end
                end
            end

            table.insert(rows, {
                id      = svc_id,
                status  = svc.status or "",
                kind    = kind,
                detail  = detail,
                retries = tostring(svc.retry_count or 0),
                uptime  = format_uptime(svc.started_at),
            })
        end
        model.svc_table = table_view.set_rows(model.svc_table, rows)
    end

    -- Update progress bars
    if model.mem_stats then
        local ms = model.mem_stats
        if ms.heap_sys > 0 then
            model.heap_bar = progress.set(model.heap_bar, ms.heap_in_use / ms.heap_sys)
        end
        if ms.stack_sys > 0 then
            model.stack_bar = progress.set(model.stack_bar, ms.stack_in_use / ms.stack_sys)
        end
    end

    return model
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------

local function init()
    local t = theme.get("dracula")

    local tb = tabs_mod.new({
        items = { "Overview", "Services", "Memory" },
    })

    -- Table columns: fixed widths for data cols, Service gets the rest
    local fixed_cols = 10 + 16 + 20 + 8 + 12  -- status + kind + detail + retries + uptime
    local table_overhead = 5 * 3 + 2          -- 5 separators * 3 chars + 2 outer spaces
    local svc_width = app.width() - fixed_cols - table_overhead

    local svc = table_view.new({
        columns = {
            { key = "id",      title = "Service",  width = svc_width },
            { key = "status",  title = "Status",   width = 10 },
            { key = "kind",    title = "Kind",     width = 16 },
            { key = "detail",  title = "Detail",   width = 20 },
            { key = "retries", title = "Retries",  width = 8, align = "right" },
            { key = "uptime",  title = "Uptime",   width = 12, align = "right" },
        },
        rows = {},
        height = CONTENT_HEIGHT - 2,
    })

    -- Progress bar width: full width minus label, percent, spacing, and bytes text
    -- "  " (2) + "Heap  " (6) + bar + " XXX%" (5) + "  " (2) + "XXX.X MB / XXX.X MB" (~22)
    local bar_width = app.width() - 37

    local heap = progress.new({
        width = bar_width,
        full_color = t.success,
        empty_color = t.muted,
    })

    local stack = progress.new({
        width = bar_width,
        full_color = t.info,
        empty_color = t.muted,
    })

    local spin = spinner.new({ preset = spinner.DOTS })

    local h = help.new({
        bindings = {
            { key = "←/→",    desc = "switch tab" },
            { key = "↑/↓",     desc = "navigate" },
            help.SEPARATOR,
            { key = "?",       desc = "toggle help" },
            { key = "q",       desc = "quit" },
        },
        width = app.width(),
    })

    local model = {
        tabs       = tb,
        theme      = t,
        spinner    = spin,
        help       = h,
        hostname   = "...",
        pid        = 0,
        cpu_count  = 0,
        max_procs  = 0,
        goroutines = 0,
        mem_stats  = nil,
        services      = {},
        modules       = {},
        total_entries  = 0,
        entry_counts   = {},
        svc_table  = svc,
        heap_bar   = heap,
        stack_bar  = stack,
    }

    model = collect_data(model)
    app.tick("1s")

    return model
end

---------------------------------------------------------------------------
-- update
---------------------------------------------------------------------------

local function update(model, msg)
    -- Tick: refresh data and schedule next tick
    if msg.kind == "tick" then
        model.spinner = spinner.update(model.spinner, msg)
        model = collect_data(model)
        app.tick("1s")
        return model
    end

    if msg.kind ~= "key" then
        return model
    end

    local key = msg.key

    -- Navigation: delegate to table_view on Services tab
    if key == "up" or key == "k" or key == "down" or key == "j" then
        local active_tab = tabs_mod.active(model.tabs)
        if active_tab == 2 then
            model.svc_table = table_view.update(model.svc_table, msg)
        end
        return model
    end

    -- Tab switching: left/right arrows
    if key == "left" then
        local current = tabs_mod.active(model.tabs)
        if current > 1 then
            model.tabs = tabs_mod.set_active(model.tabs, current - 1)
        end
        return model
    end

    if key == "right" then
        local current = tabs_mod.active(model.tabs)
        if current < 3 then
            model.tabs = tabs_mod.set_active(model.tabs, current + 1)
        end
        return model
    end

    -- Tab switching: 1, 2, 3
    if key == "1" or key == "2" or key == "3" then
        local tab_idx = (tonumber(key) or 1) --[[@as integer]]
        model.tabs = tabs_mod.set_active(model.tabs, tab_idx)
        return model
    end

    -- Toggle help
    if key == "?" then
        model.help = help.toggle(model.help)
        return model
    end

    -- Quit
    if key == "q" or key == "ctrl+c" then
        app.quit()
        return model
    end

    return model
end

---------------------------------------------------------------------------
-- view
---------------------------------------------------------------------------

local function view_overview(model)
    local t = model.theme
    local label_style = style.new():bold():foreground(t.muted)
    local value_style = style.new():foreground(t.fg --[[@as string]])

    local function row(label, value)
        return "  " .. label_style:render(string.format("%-16s", label))
            .. value_style:render(tostring(value))
    end

    local mem_str = model.mem_stats
        and format_bytes(model.mem_stats.alloc)
        or "..."
    local heap_obj = model.mem_stats
        and format_number(model.mem_stats.heap_objects)
        or "..."
    local gc_cycles = model.mem_stats
        and tostring(model.mem_stats.num_gc)
        or "..."

    local ec = model.entry_counts
    local lines = {
        row("Hostname", model.hostname),
        row("PID", model.pid),
        "",
        row("CPUs", model.cpu_count .. " (GOMAXPROCS: " .. model.max_procs .. ")"),
        row("Goroutines", model.goroutines),
        row("Memory", mem_str .. " allocated"),
        "",
        row("Registry", model.total_entries .. " entries"),
        row("  Processes", (ec["process.lua"] or 0) .. " defined"),
        row("  Services", (ec["process.service"] or 0) .. " supervised"),
        row("  Hosts", (ec["process.host"] or 0) + (ec["terminal.host"] or 0)),
        row("Modules", #model.modules .. " loaded"),
    }

    return table.concat(lines, "\n")
end

local function view_services(model)
    return table_view.view(model.svc_table)
end

local function view_memory(model)
    local t = model.theme
    local label_style = style.new():bold():foreground(t.muted)
    local value_style = style.new():foreground(t.fg --[[@as string]])
    local dim = style.dim

    local lines = {}

    local ms = model.mem_stats
    if ms then
        table.insert(lines, "  " .. label_style:render("Heap  ")
            .. progress.view(model.heap_bar)
            .. "  " .. dim(format_bytes(ms.heap_in_use) .. " / " .. format_bytes(ms.heap_sys)))
        table.insert(lines, "  " .. label_style:render("Stack ")
            .. progress.view(model.stack_bar)
            .. "  " .. dim(format_bytes(ms.stack_in_use) .. " / " .. format_bytes(ms.stack_sys)))
        table.insert(lines, "")

        local function stat(label, value)
            return "  " .. label_style:render(string.format("%-18s", label))
                .. value_style:render(format_number(value))
        end

        table.insert(lines, stat("Heap Alloc", ms.heap_alloc))
        table.insert(lines, stat("Heap Sys", ms.heap_sys))
        table.insert(lines, stat("Heap Objects", ms.heap_objects))
        table.insert(lines, stat("Heap Idle", ms.heap_idle))
        table.insert(lines, stat("Heap Released", ms.heap_released))
        table.insert(lines, "")
        table.insert(lines, stat("Stack In Use", ms.stack_in_use))
        table.insert(lines, stat("Stack Sys", ms.stack_sys))
        table.insert(lines, "")
        table.insert(lines, stat("Total Alloc", ms.total_alloc))
        table.insert(lines, stat("Sys Total", ms.sys))
        table.insert(lines, stat("GC Cycles", ms.num_gc))
        table.insert(lines, stat("Next GC", ms.next_gc))
    else
        table.insert(lines, dim("  Collecting data..."))
    end

    return table.concat(lines, "\n")
end

local function view(model)
    local t = model.theme

    -- Title with spinner
    local title_style = style.new()
        :bold()
        :foreground(t.primary)
        :padding(0, 1)

    local spin_view = spinner.view(model.spinner)
    local title = spin_view .. " " .. title_style:render("System Monitor")
    local subtitle = style.dim("  " .. model.hostname .. " (PID: " .. model.pid .. ")")

    -- Tab content (padded to fixed height)
    local active_tab = tabs_mod.active(model.tabs)
    local content
    if active_tab == 1 then
        content = view_overview(model)
    elseif active_tab == 2 then
        content = view_services(model)
    else
        content = view_memory(model)
    end

    -- Separator
    local sep = string.rep("─", app.width())

    -- Build output with exact line count — every frame identical structure
    local out = {}
    out[1] = title .. subtitle
    out[2] = ""
    out[3] = tabs_mod.view(model.tabs)
    out[4] = sep

    -- Pad content lines into fixed slots
    local content_lines = {}
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(content_lines, line)
    end
    for i = 1, CONTENT_HEIGHT do
        out[4 + i] = content_lines[i] or ""
    end

    local base = 4 + CONTENT_HEIGHT
    out[base + 1] = sep
    out[base + 2] = help.view(model.help)

    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- main
---------------------------------------------------------------------------

local function main()
    app.run({
        init       = init,
        update     = update,
        view       = view,
        alt_screen = true,
    })
    return 0
end

return { main = main }
