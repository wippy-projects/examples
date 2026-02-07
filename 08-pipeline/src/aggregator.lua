local logger = require("logger")

--- Stage 3: Aggregate enriched data.
--- Counts events by type and max severity, sends summary back to CLI.
local function main()
    local pid = process.pid()
    local inbox = process.inbox()
    local events = process.events()

    logger:info("Aggregator ready", { pid = pid })

    local by_type = {}
    local by_user = {}
    local total = 0
    local max_severity = 0

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

            if topic == "formatted" then
                local data = msg:payload():data()
                total = total + 1
                by_type[data.event_type] = (by_type[data.event_type] or 0) + 1
                by_user[data.user] = (by_user[data.user] or 0) + 1
                if data.severity > max_severity then
                    max_severity = data.severity
                end

            elseif topic == "done" then
                -- Send summary back to the requester
                local reply_to = tostring(msg:payload():data())
                local summary = {
                    total = total,
                    by_type = by_type,
                    by_user = by_user,
                    max_severity = max_severity
                }
                logger:info("Aggregation complete", summary)
                process.send(reply_to, "summary", summary)
                return 0
            end
        end
    end
end

return { main = main }
