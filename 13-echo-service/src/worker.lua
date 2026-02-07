local time = require("time")

--- Worker: receives sender PID and data, echoes back uppercased.
--- Each worker handles exactly one message and exits.
local function main(sender_pid, data)
    time.sleep("100ms")

    local response = {
        data = string.upper(data),
        worker = tostring(process.pid())
    }

    process.send(sender_pid, "echo_response", response)

    return 0
end

return { main = main }
