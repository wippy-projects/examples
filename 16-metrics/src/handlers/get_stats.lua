local http = require("http")
local json = require("json")
local metrics = require("metrics")
local system = require("system")

--- GET /api/stats — return runtime statistics.
--- Demonstrates the system module for memory and goroutine info.
local function handler()
    local res = http.response()

    metrics.counter_inc("stats_requests_total", {})

    local mem = system.memory.stats()
    local goroutines = system.runtime.goroutines()

    res:set_status(200)
    res:write_json({
        runtime = {
            goroutines = goroutines,
            memory = mem
        }
    })
end

return { handler = handler }
