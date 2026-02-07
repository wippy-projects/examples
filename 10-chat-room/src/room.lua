local logger = require("logger")
local events = require("events")
local registry = require("registry")

type ChatMessage = {user: string, text: string, time: integer}

--- Chat room process — one per room.
--- Maintains members and history. Emits events on activity.
--- Registers in process.registry for name lookup.
--- Registers in app registry as a discoverable room.
local function main(room_name: string)
    local pid = process.pid()
    local members = {}   -- { [username] = true }
    local history = {}   -- { {user, text, time} }

    -- Register by name for message routing
    process.registry.register("room:" .. room_name)

    -- Register in app registry so rooms are discoverable
    local snap = registry.snapshot()
    local changes = snap:changes()
    changes:create({
        id = "app:room." .. room_name,
        kind = "registry.entry",
        meta = {
            type = "chat.room",
            title = room_name
        },
        data = { created_by = pid }
    })
    changes:apply()

    logger:info("Room created", { room = room_name, pid = pid })
    events.send("chat", "room.created", "/rooms/" .. room_name, { room = room_name })

    local inbox = process.inbox()
    local evts = process.events()

    while true do
        local r = channel.select {
            inbox:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                process.registry.unregister("room:" .. room_name)
                logger:info("Room closed", { room = room_name })
                return 0
            end
        else
            local msg = r.value
            local topic = msg:topic()
            local data = msg:payload():data()

            if topic == "join" then
                members[data.user] = true
                logger:info("User joined", { room = room_name, user = data.user })
                events.send("chat", "user.joined", "/rooms/" .. room_name, {
                    room = room_name,
                    user = data.user
                })

            elseif topic == "leave" then
                members[data.user] = nil
                logger:info("User left", { room = room_name, user = data.user })
                events.send("chat", "user.left", "/rooms/" .. room_name, {
                    room = room_name,
                    user = data.user
                })

            elseif topic == "message" then
                local entry = {
                    user = data.user,
                    text = data.text,
                    time = os.time()
                }
                table.insert(history, entry)
                logger:info(string.format("[#%s] %s: %s", room_name, data.user, data.text))
                events.send("chat", "message.sent", "/rooms/" .. room_name, {
                    room = room_name,
                    user = data.user,
                    text = data.text
                })

            elseif topic == "get_info" then
                local member_list = {}
                for u, _ in pairs(members) do table.insert(member_list, u) end

                local last = {}
                local start = math.max(1, #history - 4)
                for i = start, #history do
                    table.insert(last, history[i])
                end

                process.send(tostring(data.reply_to), "room_info", {
                    room = room_name,
                    members = member_list,
                    message_count = #history,
                    last_messages = last
                })

            elseif topic == "close" then
                process.registry.unregister("room:" .. room_name)
                events.send("chat", "room.closed", "/rooms/" .. room_name, { room = room_name })
                logger:info("Room closed by request", { room = room_name })
                return 0
            end
        end
    end
end

return { main = main }
