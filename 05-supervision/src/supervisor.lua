local io = require("io")
local time = require("time")

--- Manual supervisor: spawns a worker, watches for crashes, restarts.
--- Demonstrates spawn_monitored + EXIT events + restart with backoff.
---
--- Run: wippy run -x app:supervisor
local function main()
    io.print("=== Supervision: Let It Crash ===")
    io.print("")
    io.print("Spawning an unstable worker that randomly crashes.")
    io.print("Supervisor will catch EXIT events and restart it.")
    io.print("")

    local max_restarts = 5
    local restarts = 0
    local events = process.events()

    -- Spawn first worker
    local worker_pid = process.spawn_monitored("app:unstable_worker", "app:processes")
    io.print("[supervisor] Started worker: " .. worker_pid)

    while restarts < max_restarts do
        local event = events:receive()

        if event.kind == process.event.EXIT then
            if event.result.error then
                restarts = restarts + 1
                io.print("")
                io.print(string.format(
                    "[supervisor] Worker %s crashed! (%d/%d)",
                    event.from, restarts, max_restarts
                ))
                io.print("[supervisor] Error: " .. tostring(event.result.error))

                if restarts < max_restarts then
                    -- Backoff before restart
                    local delay = restarts
                    io.print(string.format(
                        "[supervisor] Restarting in %ds...", delay
                    ))
                    time.sleep(tostring(delay) .. "s")

                    worker_pid = process.spawn_monitored("app:unstable_worker", "app:processes")
                    io.print("[supervisor] New worker: " .. worker_pid)
                end
            else
                io.print("[supervisor] Worker exited cleanly: " .. event.from)
                break
            end
        end
    end

    io.print("")
    io.print(string.format(
        "Supervisor done. Worker crashed %d times and was restarted each time.",
        restarts
    ))
    io.print("In production, use process.service for declarative supervision.")
    return 0
end

return { main = main }
