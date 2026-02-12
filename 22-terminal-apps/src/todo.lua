--- TUI Todo List — interactive todo manager using the Elm Architecture.
---
--- Demonstrates: app runtime, textinput, list, tabs, help, style, layout, theme.
---
--- Controls:
---   ↑/↓ or j/k   move cursor
---   enter         toggle done on selected item
---   a / i         start typing a new todo
---   d / x         delete selected item
---   ←/→           switch tab
---   1 / 2 / 3     jump to tab (All / Active / Done)
---   ?             toggle full help
---   q             quit

local app       = require("app")
local style     = require("style")
local color     = require("color")
local textinput = require("textinput")
local list      = require("list")
local tabs      = require("tabs")
local help      = require("help")
local layout    = require("layout")
local theme     = require("theme")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Filter todos based on the active tab index.
---   1 = All, 2 = Active, 3 = Done
local function filter_todos(todos, tab_index)
    if tab_index == 1 then return todos end
    local result = {}
    for _, todo in ipairs(todos) do
        if tab_index == 2 and not todo.done then
            table.insert(result, todo)
        elseif tab_index == 3 and todo.done then
            table.insert(result, todo)
        end
    end
    return result
end

--- Convert todo items to list-compatible items with checkbox prefix.
local function todos_to_list_items(todos)
    local items = {}
    for _, todo in ipairs(todos) do
        local prefix = todo.done and "[x] " or "[ ] "
        table.insert(items, { title = prefix .. todo.text })
    end
    return items
end

--- Rebuild the list sub-model from current todos + active tab.
local function refresh_list(model)
    local filtered = filter_todos(model.todos, tabs.active(model.tabs))
    model.list = list.set_items(model.list, todos_to_list_items(filtered))
    return model
end

--- Map the selected index in the (possibly filtered) list back to the
--- original index in model.todos.
local function find_real_index(model)
    local sel = list.selected_index(model.list)
    if not sel or sel < 1 then return nil end

    local active_tab = tabs.active(model.tabs)
    if active_tab == 1 then return sel end

    local count = 0
    for i, todo in ipairs(model.todos) do
        local matches = (active_tab == 2 and not todo.done)
                     or (active_tab == 3 and todo.done)
        if matches then
            count = count + 1
            if count == sel then return i end
        end
    end
    return nil
end

--- Count completed todos.
local function done_count(todos)
    local n = 0
    for _, todo in ipairs(todos) do
        if todo.done then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------

local function init()
    local t = theme.get("dracula")

    local l = list.new({
        items = {},
        height = 15,
        no_items_text = "No todos yet. Press 'a' to add one.",
    })

    local tb = tabs.new({
        items = { "All", "Active", "Done" },
    })

    local ti = textinput.new({
        placeholder = "What needs to be done?",
        prompt = "> ",
    })
    textinput.blur(ti)

    local h = help.new({
        bindings = {
            { key = "↑/↓",     desc = "move" },
            { key = "enter",   desc = "toggle done" },
            { key = "a",       desc = "add todo" },
            { key = "d",       desc = "delete" },
            help.SEPARATOR,
            { key = "←/→",    desc = "switch tab" },
            { key = "?",       desc = "toggle help" },
            { key = "q",       desc = "quit" },
        },
        width = 70,
    })

    return {
        todos = {},
        list  = l,
        tabs  = tb,
        input = ti,
        help  = h,
        theme = t,
        mode  = "list",  -- "list" or "input"
    }
end

---------------------------------------------------------------------------
-- update
---------------------------------------------------------------------------

local function update(model, msg)
    if msg.kind ~= "key" then
        return model
    end

    local key = msg.key

    -- ── Input mode: delegate to textinput ───────────────────
    if model.mode == "input" then
        -- Enter: submit the todo
        if key == "enter" then
            local text = textinput.value(model.input)
            if text ~= "" then
                table.insert(model.todos, { text = text, done = false })
                model = refresh_list(model)
            end
            model.input = textinput.reset(model.input)
            textinput.blur(model.input)
            model.mode = "list"
            return model
        end

        -- Escape: cancel input
        if key == "escape" then
            model.input = textinput.reset(model.input)
            textinput.blur(model.input)
            model.mode = "list"
            return model
        end

        -- All other keys go to textinput
        model.input = textinput.update(model.input, msg)
        return model
    end

    -- ── List mode ───────────────────────────────────────────

    -- Navigation: up/down arrows or j/k
    if key == "up" or key == "k" then
        model.list = list.update(model.list, {kind = "key", key = "up"})
        return model
    end

    if key == "down" or key == "j" then
        model.list = list.update(model.list, {kind = "key", key = "down"})
        return model
    end

    -- Enter or space: toggle done on selected
    if key == "enter" or key == " " then
        local idx = find_real_index(model)
        if idx then
            model.todos[idx].done = not model.todos[idx].done
            model = refresh_list(model)
        end
        return model
    end

    -- Add: switch to input mode
    if key == "a" or key == "i" then
        model.mode = "input"
        textinput.focus(model.input)
        return model
    end

    -- Delete
    if key == "d" or key == "x" then
        local idx = find_real_index(model)
        if idx then
            table.remove(model.todos, idx)
            model = refresh_list(model)
        end
        return model
    end

    -- Tab switching: left/right arrows
    if key == "left" then
        local current = tabs.active(model.tabs)
        if current > 1 then
            model.tabs = tabs.set_active(model.tabs, current - 1)
            model = refresh_list(model)
        end
        return model
    end

    if key == "right" then
        local current = tabs.active(model.tabs)
        if current < 3 then
            model.tabs = tabs.set_active(model.tabs, current + 1)
            model = refresh_list(model)
        end
        return model
    end

    -- Tab switching: 1, 2, 3
    if key == "1" or key == "2" or key == "3" then
        local tab_idx = tonumber(key) or 1
        model.tabs = tabs.set_active(model.tabs, tab_idx --[[@as integer]])
        model = refresh_list(model)
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

local function view(model)
    local t = model.theme

    -- Title
    local title_style = style.new()
        :bold()
        :foreground(t.primary)
        :padding(0, 1)

    local total = #model.todos
    local completed = done_count(model.todos)
    local title = title_style:render("TODO List")
    local counter = style.dim(string.format("  %d/%d done", completed, total))

    -- Tabs
    local tabs_view = tabs.view(model.tabs)

    -- List (always use the list component to keep a fixed view height)
    local list_view = list.view(model.list)

    -- Input area
    local input_view
    if model.mode == "input" then
        input_view = textinput.view(model.input)
    else
        input_view = style.dim("Press 'a' to add a todo")
    end

    -- Status bar
    local status = help.view(model.help)

    -- Compose
    return layout.vertical({
        title .. counter,
        "",
        tabs_view,
        "",
        list_view,
        "",
        input_view,
        "",
        status,
    }, "left", 0)
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
