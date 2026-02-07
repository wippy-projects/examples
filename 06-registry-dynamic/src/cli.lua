local io = require("io")
local registry = require("registry")
local json = require("json")

--- Demonstrates dynamic registry: query entries by custom type,
--- add new entries at runtime, query again.
---
--- Run: wippy run -x app:cli
local function main(): integer
    io.print("=== Dynamic Registry ===")
    io.print("")

    -- Show initial version and tools from YAML
    local snap, err = registry.snapshot()
    if err then
        io.print("Error getting snapshot: " .. tostring(err))
        return 1
    end

    io.print("1) Tools registered in YAML (version " .. snap:version():string() .. "):")
    io.print("")
    list_tools()

    -- Add first tool at runtime
    io.print("2) Adding Weather tool...")
    io.print("")

    local changes = snap:changes()
    changes:create({
        id = "app:tool.weather",
        kind = "registry.entry",
        meta = {
            type = "tool",
            title = "Weather",
            description = "Gets current weather for a location"
        },
        data = {}
    })

    local version, apply_err = changes:apply()
    if apply_err then
        io.print("Error applying changes: " .. tostring(apply_err))
        return 1
    end
    io.print("   Registry version: " .. version:string())
    io.print("")
    list_tools()

    -- Add second tool in a new transaction
    io.print("3) Adding Web Search tool...")
    io.print("")

    snap, err = registry.snapshot()
    if err then
        io.print("Error getting snapshot: " .. tostring(err))
        return 1
    end

    changes = snap:changes()
    changes:create({
        id = "app:tool.search",
        kind = "registry.entry",
        meta = {
            type = "tool",
            title = "Web Search",
            description = "Searches the web for information"
        },
        data = {}
    })

    version, apply_err = changes:apply()
    if apply_err then
        io.print("Error applying changes: " .. tostring(apply_err))
        return 1
    end
    io.print("   Registry version: " .. version:string())
    io.print("")
    list_tools()

    -- Delete a tool
    io.print("4) Removing Summarizer tool...")
    io.print("")

    snap, err = registry.snapshot()
    if err then
        io.print("Error getting snapshot: " .. tostring(err))
        return 1
    end

    changes = snap:changes()
    changes:delete("app:tool.summarizer")

    version, apply_err = changes:apply()
    if apply_err then
        io.print("Error applying changes: " .. tostring(apply_err))
        return 1
    end
    io.print("   Registry version: " .. version:string())
    io.print("")
    list_tools()

    io.print("Registry is the source of truth.")
    io.print("Each changes:apply() bumps the version atomically.")
    return 0
end

function list_tools()
    local entries, err = registry.find({ kind = "registry.entry" })
    if err then
        io.print("Error: " .. tostring(err))
        return
    end

    local count = 0
    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "tool" then
            count = count + 1
            io.print(string.format("   [%s] %s — %s",
                entry.id,
                entry.meta.title or "?",
                entry.meta.description or ""
            ))
        end
    end

    if count == 0 then
        io.print("   (none)")
    end
    io.print("")
end

return { main = main }
