local io = require("io")
local time = require("time")
local json = require("json")

--- Orchestrator: builds a 4-stage pipeline of processes.
--- Data flows: CLI → Parser → Transformer → Formatter → Aggregator → CLI
---
--- Run: wippy run -x app:cli
local function main()
    io.print("=== Pipeline: Process Chain ===")
    io.print("")
    io.print("Data flows through 4 processes:")
    io.print("  Parser → Transformer → Formatter → Aggregator")
    io.print("")

    -- Spawn pipeline in reverse order (each needs the next stage's PID)
    local aggregator_pid = process.spawn_monitored("app:aggregator", "app:processes")
    local formatter_pid = process.spawn_monitored("app:formatter", "app:processes", aggregator_pid)
    local transformer_pid = process.spawn_monitored("app:transformer", "app:processes", formatter_pid)
    local parser_pid = process.spawn_monitored("app:parser", "app:processes", transformer_pid)

    time.sleep("200ms")

    -- Simulated log lines: "LEVEL|event_type|user"
    local log_lines = {
        "INFO|user.login|Alice",
        "INFO|user.login|Bob",
        "WARN|user.failed_login|Charlie",
        "INFO|page.view|Alice",
        "ERROR|payment.failed|Bob",
        "INFO|user.login|Alice",
        "INFO|user.logout|Bob",
        "WARN|rate.limit|Charlie",
        "INFO|page.view|Alice",
        "FATAL|db.connection|System",
    }

    io.print("Feeding " .. #log_lines .. " log lines into pipeline:")
    io.print("")

    for _, line in ipairs(log_lines) do
        io.print("  → " .. line)
        process.send(parser_pid, "raw_line", line)
        time.sleep("100ms")
    end

    -- Signal end of data, pass our PID (as string) for the reply
    process.send(parser_pid, "done", tostring(process.pid()))

    io.print("")
    io.print("Waiting for aggregated results...")

    -- Wait for summary from aggregator
    local inbox = process.inbox()
    local timeout = time.after("5s")
    local r = channel.select {
        inbox:case_receive(),
        timeout:case_receive()
    }

    if r.channel == timeout then
        io.print("Timeout waiting for results!")
        return 1
    end

    local summary = r.value:payload():data()
    io.print("")
    io.print("=== Summary ===")
    io.print("Total events: " .. summary.total)
    io.print("Max severity: " .. summary.max_severity)
    io.print("")

    io.print("By event type:")
    for k, v in pairs(summary.by_type) do
        io.print("  " .. k .. ": " .. v)
    end

    io.print("")
    io.print("By user:")
    for k, v in pairs(summary.by_user) do
        io.print("  " .. k .. ": " .. v)
    end

    io.print("")
    io.print("Each stage was an isolated process. Data flowed via messages.")
    return 0
end

return { main = main }
