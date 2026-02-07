local logger = require("logger")

--- A key-value store implemented as a process.
--- State lives in process memory — no external storage needed.
--- Clients communicate via messages (get/set/delete/keys).
local function main()
    local pid = process.pid()
    local data = {}
    local ops = 0

    process.registry.register("kv")
    logger:info("KV server ready", { pid = pid })

    local inbox = process.inbox()
    local events = process.events()

    while true do
        local r = channel.select {
            inbox:case_receive(),
            events:case_receive()
        }

        if r.channel == events then
            if r.value.kind == process.event.CANCEL then
                process.registry.unregister("kv")
                logger:info("KV server stopped", { ops = ops, keys = count_keys(data) })
                return 0
            end
        else
            local msg = r.value
            local topic = msg:topic()
            local payload = msg:payload():data()
            ops = ops + 1

            if topic == "set" then
                data[payload.key] = payload.value
                logger:info("SET", { key = payload.key })
                process.send(tostring(payload.reply_to), "kv_response", {
                    op = "set",
                    key = payload.key,
                    ok = true
                })

            elseif topic == "get" then
                local value = data[payload.key]
                process.send(tostring(payload.reply_to), "kv_response", {
                    op = "get",
                    key = payload.key,
                    value = value,
                    found = value ~= nil
                })

            elseif topic == "delete" then
                local existed = data[payload.key] ~= nil
                data[payload.key] = nil
                process.send(tostring(payload.reply_to), "kv_response", {
                    op = "delete",
                    key = payload.key,
                    deleted = existed
                })

            elseif topic == "keys" then
                local keys = {}
                for k, _ in pairs(data) do
                    table.insert(keys, k)
                end
                process.send(tostring(payload.reply_to), "kv_response", {
                    op = "keys",
                    keys = keys,
                    count = #keys
                })

            elseif topic == "stats" then
                process.send(tostring(payload.reply_to), "kv_response", {
                    op = "stats",
                    total_ops = ops,
                    total_keys = count_keys(data)
                })
            end
        end
    end
end

function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

return { main = main }
