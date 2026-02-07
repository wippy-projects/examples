local logger = require("logger")

type ParsedEvent = {level: string, event_type: string, user: string, raw: string}

--- Stage 1: Parse raw log lines into structured data.
--- Receives next_pid (transformer) as argument.
local function main(next_pid: string)
    local pid = process.pid()
    local inbox = process.inbox()
    local events = process.events()

    logger:info("Parser ready", { pid = pid })

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

            if topic == "raw_line" then
                local line = tostring(msg:payload():data())

                -- Parse "LEVEL|event_type|user" format
                local level, event_type, user = string.match(line, "^(%w+)|(%S+)|(%S+)$")

                if level then
                    local parsed = {
                        level = level,
                        event_type = event_type,
                        user = user,
                        raw = line
                    }
                    logger:info("Parsed", parsed)
                    process.send(next_pid, "parsed", parsed)
                else
                    logger:warn("Failed to parse", { line = line })
                end

            elseif topic == "done" then
                process.send(next_pid, "done", msg:payload():data())
                return 0
            end
        end
    end
end

return { main = main }
