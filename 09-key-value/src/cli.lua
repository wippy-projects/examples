local io = require("io")
local time = require("time")

--- KV client: sends commands to kv_server process, displays results.
--- Demonstrates request/reply pattern via messages.
---
--- Run: wippy run -x app:cli
local function main()
    io.print("=== Key-Value Store as a Process ===")
    io.print("")

    local my_pid = tostring(process.pid())
    local inbox = process.inbox()

    -- Wait for KV server to start
    time.sleep("300ms")

    -- Helper: wait for a reply from the KV server
    local function kv_wait()
        local timeout = time.after("2s")
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive()
        }
        if r.channel == timeout then
            io.print("  Timeout waiting for KV response!")
            return nil
        end
        return r.value:payload():data()
    end

    -- SET some values
    io.print("Setting values:")
    local entries = {
        { key = "name", value = "Wippy" },
        { key = "version", value = "0.1" },
        { key = "lang", value = "Lua" },
        { key = "model", value = "Actor" },
        { key = "overhead", value = "13KB" },
    }

    for _, e in ipairs(entries) do
        process.send("kv", "set", { key = e.key, value = e.value, reply_to = my_pid })
        local res = kv_wait()
        if res then
            io.print(string.format("  SET %s = %s  → ok: %s", e.key, e.value, tostring(res.ok)))
        end
    end
    io.print("")

    -- GET values
    io.print("Getting values:")
    local keys_to_get = { "name", "version", "lang", "missing_key" }
    for _, key in ipairs(keys_to_get) do
        process.send("kv", "get", { key = key, reply_to = my_pid })
        local res = kv_wait()
        if res then
            if res.found then
                io.print(string.format("  GET %s → %s", key, tostring(res.value)))
            else
                io.print(string.format("  GET %s → (not found)", key))
            end
        end
    end
    io.print("")

    -- DELETE
    io.print("Deleting 'lang':")
    process.send("kv", "delete", { key = "lang", reply_to = my_pid })
    local del_res = kv_wait()
    if del_res then
        io.print("  Deleted: " .. tostring(del_res.deleted))
    end
    io.print("")

    -- LIST keys
    io.print("Listing all keys:")
    process.send("kv", "keys", { reply_to = my_pid })
    local keys_res = kv_wait()
    if keys_res then
        io.print("  Keys (" .. keys_res.count .. "): " .. table.concat(keys_res.keys, ", "))
    end
    io.print("")

    -- STATS
    io.print("Server stats:")
    process.send("kv", "stats", { reply_to = my_pid })
    local stats = kv_wait()
    if stats then
        io.print("  Total operations: " .. stats.total_ops)
        io.print("  Total keys: " .. stats.total_keys)
    end

    io.print("")
    io.print("The KV store is a process. State lives in memory.")
    io.print("No database, no disk — just actor state + messages.")

    return 0
end

return { main = main }
