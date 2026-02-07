local logger = require("logger")
local time = require("time")

--- An unstable worker that randomly crashes.
--- Demonstrates "let it crash" philosophy:
--- don't handle errors defensively, let supervisor restart.
local function main()
    local pid = process.pid()
    logger:info("Worker started", { pid = pid })

    local tick = 0
    while true do
        tick = tick + 1
        time.sleep("500ms")

        -- Randomly crash ~30% of the time
        if math.random(100) <= 30 then
            logger:warn("Worker crashing!", { pid = pid, tick = tick })
            error("something went wrong at tick " .. tick)
        end

        logger:info("Worker tick", { pid = pid, tick = tick })
    end
end

return { main = main }
