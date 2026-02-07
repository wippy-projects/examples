local io = require("io")
local time = require("time")
local registry = require("registry")

local function send_to_room(room_name, topic, data)
    local pid = process.registry.lookup("room:" .. room_name)
    if pid then
        process.send(pid, topic, data)
    end
end

--- Chat simulator: creates rooms, simulates users chatting.
--- Combines: processes, messages, events, registry, process.registry.
---
--- Run: wippy run -x app:cli
local function main()
    io.print("=== Chat Room: Everything Combined ===")
    io.print("")
    io.print("Features used:")
    io.print("  - Process per room (actor with isolated state)")
    io.print("  - Messages for join/leave/chat/info")
    io.print("  - Event bus for notifications (loose coupling)")
    io.print("  - Registry for room discovery")
    io.print("  - process.registry for name-based routing")
    io.print("")

    -- Wait for notification service
    time.sleep("300ms")

    -- Create two rooms
    io.print("Creating rooms...")
    process.spawn("app:room", "app:processes", "general")
    process.spawn("app:room", "app:processes", "random")
    time.sleep("300ms")
    io.print("")

    -- Simulate users joining
    io.print("Users joining rooms...")
    send_to_room("general", "join", { user = "Alice" })
    send_to_room("general", "join", { user = "Bob" })
    send_to_room("random",  "join", { user = "Alice" })
    send_to_room("random",  "join", { user = "Charlie" })
    time.sleep("200ms")
    io.print("")

    -- Simulate chat
    io.print("Chatting...")
    local messages = {
        { room = "general", user = "Alice",   text = "Hey everyone!" },
        { room = "general", user = "Bob",     text = "Hi Alice!" },
        { room = "random",  user = "Charlie", text = "Anyone here?" },
        { room = "random",  user = "Alice",   text = "I'm in both rooms!" },
        { room = "general", user = "Alice",   text = "Wippy makes this easy" },
        { room = "general", user = "Bob",     text = "Each room is its own process" },
        { room = "random",  user = "Charlie", text = "And messages never mix!" },
    }

    for _, m in ipairs(messages) do
        send_to_room(m.room, "message", { user = m.user, text = m.text })
        time.sleep("200ms")
    end
    io.print("")

    -- Query room info
    io.print("Querying room info...")
    local my_pid = tostring(process.pid())
    local inbox = process.inbox()

    for _, room_name in ipairs({"general", "random"}) do
        send_to_room(room_name, "get_info", { reply_to = my_pid })

        local timeout = time.after("2s")
        local r = channel.select {
            inbox:case_receive(),
            timeout:case_receive()
        }

        if r.channel ~= timeout then
            local info = r.value:payload():data()
            io.print(string.format(
                "  #%s: %d members (%s), %d messages",
                info.room,
                #info.members,
                table.concat(info.members, ", "),
                info.message_count
            ))
        end
    end
    io.print("")

    -- Discover rooms via registry
    io.print("Discovering rooms via registry:")
    local entries, err = registry.find({ ["meta.type"] = "chat.room" })
    if not err then
        for _, entry in ipairs(entries) do
            io.print("  Found: #" .. entry.meta.title .. " (" .. entry.id .. ")")
        end
    end
    io.print("")

    -- Users leave, close rooms
    io.print("Cleaning up...")
    send_to_room("general", "leave", { user = "Bob" })
    send_to_room("general", "close", {})
    send_to_room("random", "close", {})
    time.sleep("500ms")

    io.print("")
    io.print("Done! Each room was a process, events notified all subscribers,")
    io.print("and registry made rooms discoverable. No shared state anywhere.")
    return 0
end

return { main = main }
