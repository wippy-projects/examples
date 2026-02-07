local logger = require("logger")

--- Stage 2: Transform/enrich parsed data.
--- Normalizes level, adds severity score.
local function main(next_pid)
    local pid = process.pid()
    local inbox = process.inbox()
    local events = process.events()

    logger:info("Transformer ready", { pid = pid })

    local function severity(level)
        if level == "INFO" then return 1
        elseif level == "WARN" then return 2
        elseif level == "ERROR" then return 3
        elseif level == "FATAL" then return 4
        else return 0 end
    end

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

            if topic == "parsed" then
                local data = msg:payload():data()

                -- Enrich with severity and normalized fields
                local level = tostring(string.upper(data.level))
                local enriched = {
                    level = level,
                    severity = severity(level),
                    event_type = data.event_type,
                    user = string.lower(data.user),
                    raw = data.raw
                }

                logger:info("Transformed", enriched)
                process.send(next_pid, "enriched", enriched)

            elseif topic == "done" then
                process.send(next_pid, "done", msg:payload():data())
                return 0
            end
        end
    end
end

return { main = main }
