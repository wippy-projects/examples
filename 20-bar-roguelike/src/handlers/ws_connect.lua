local http = require("http")
local json = require("json")

local function handler()
    local req = http.request()
    local res = http.response()

    local pid = process.spawn("app:session_process", "app:processes")

    res:set_header("X-WS-Relay", json.encode({
        target_pid = tostring(pid),
        message_topic = "ws.message",
        heartbeat_interval = "30s",
    }))
end

return { handler = handler }
