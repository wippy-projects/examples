local logger = require("logger")
local events = require("events")
local time = require("time")

--- Publisher service: emits user lifecycle events to the event bus.
--- Two subscribers (audit_log, counter) react independently.
---
--- Run: wippy run
local function main()
    -- Wait for subscribers to start
    time.sleep("500ms")

    logger:info("Publisher started, emitting user events...")

    local user_events = {
        { kind = "user.created",  path = "/users/1", data = { name = "Alice" } },
        { kind = "user.created",  path = "/users/2", data = { name = "Bob" } },
        { kind = "user.login",    path = "/users/1", data = { name = "Alice" } },
        { kind = "user.updated",  path = "/users/1", data = { name = "Alice", email = "alice@new.com" } },
        { kind = "user.login",    path = "/users/2", data = { name = "Bob" } },
        { kind = "user.created",  path = "/users/3", data = { name = "Charlie" } },
        { kind = "user.login",    path = "/users/1", data = { name = "Alice" } },
        { kind = "user.deleted",  path = "/users/2", data = { name = "Bob" } },
    }

    for _, evt in ipairs(user_events) do
        logger:info("Publishing", { kind = evt.kind, path = evt.path })
        events.send("users", evt.kind, evt.path, evt.data)
        time.sleep("300ms")
    end

    logger:info("All events published. Publisher doesn't know who listens.")
    return 0
end

return { main = main }
