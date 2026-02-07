local logger = require("logger")
local time = require("time")

--- Shared job loop: runs a named task on a fixed interval.
--- Each job is a separate process, started via process.service.
local function run_job(name, interval)
    logger:info("Job started", { name = name, interval = interval, pid = process.pid() })

    local evts = process.events()
    local run = 0

    while true do
        local timer = time.after(interval)
        local r = channel.select {
            timer:case_receive(),
            evts:case_receive()
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                logger:info("Job stopped", { name = name, runs = run })
                return 0
            end
        else
            run = run + 1
            logger:info("TICK " .. name, { run = run })
        end
    end
end

local function heartbeat() return run_job("heartbeat", "1s") end
local function cleanup()   return run_job("cleanup",   "3s") end
local function report()    return run_job("report",    "5s") end
local function backup()    return run_job("backup",    "7s") end

return {
    heartbeat = heartbeat,
    cleanup = cleanup,
    report = report,
    backup = backup,
}
