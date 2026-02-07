local io = require("io")
local time = require("time")

--- Echo client: sends messages to the relay, waits for uppercased responses.
--- Interactive CLI — type messages, see echoed results.
---
--- Run: wippy run -x app:cli
local function main()
    local inbox = process.inbox()

    -- Wait for relay to register
    time.sleep("200ms")

    io.print("Echo Client")
    io.print("Type messages to echo. Ctrl+C to exit.")
    io.print("")

    while true do
        io.write("> ")
        local input = io.readline()

        if not input or #input == 0 then
            break
        end

        local msg = {
            sender = tostring(process.pid()),
            data = input
        }
        local ok, err = process.send("relay", "echo", msg)
        if err then
            io.print("  error: relay not available")
        else
            local timeout = time.after("2s")
            local r = channel.select {
                inbox:case_receive(),
                timeout:case_receive()
            }

            if r.channel == timeout then
                io.print("  timeout")
            else
                local resp_msg = r.value
                if resp_msg:topic() == "echo_response" then
                    local resp = resp_msg:payload():data()
                    io.print("  " .. resp.data)
                    io.print("  from worker: " .. tostring(resp.worker))
                end
            end
        end
    end

    io.print("")
    io.print("Goodbye!")
    return 0
end

return { main = main }
