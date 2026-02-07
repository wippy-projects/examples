local logger = require("logger")
local json = require("json")

--- Stage 3: Format enriched data as JSON strings.
--- Demonstrates the json module in a pipeline context.
local function main(next_pid)
    local pid = process.pid()
    local inbox = process.inbox()
    local events = process.events()

    logger:info("Formatter ready", { pid = pid })

    while true do
        local r = channel.select {
            inbox:case_receive(),
            events:case_receive()
        }

        if r.channel == events then
            if r.value.kind == process.event.CANCEL then return 0 end
        else
            local msg = r.value
            local topic = msg:topic()

            if topic == "enriched" then
                local data = msg:payload():data()

                -- Convert to JSON and back to prove serialization
                local json_str = json.encode(data)
                local decoded = json.decode(json_str)

                logger:info("Formatted", { json = json_str })
                process.send(next_pid, "formatted", decoded)

            elseif topic == "done" then
                process.send(next_pid, "done", msg:payload():data())
                return 0
            end
        end
    end
end

return { main = main }
