--- Simple background worker — loops with a periodic tick.
--- Used to demonstrate multiple supervised services in the system monitor.

local time = require("time")

local function main()
    local evts = process.events()

    while true do
        local timer = time.after("3s")
        local r = channel.select {
            timer:case_receive(),
            evts:case_receive(),
        }
        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                return 0
            end
        end
    end
end

return { main = main }
