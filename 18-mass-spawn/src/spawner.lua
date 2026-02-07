local logger = require("logger")
local env = require("env")
local time = require("time")

--- Parse a duration string (e.g., "50ms", "2s") into milliseconds.
local function parse_ms(str: string): number
    local d, err = time.parse_duration(str)
    if err then return 0 end
    return d:milliseconds()
end

--- Random integer in [min, max].
local function rand_between(min_val: number, max_val: number): number
    if min_val >= max_val then return min_val end
    return math.random(math.floor(min_val), math.floor(max_val))
end

--- Spawner: spawns N long-lived worker processes, then monitors their ticks.
--- Each worker runs a while loop with a periodic ticker, sending "tick" messages
--- back to this spawner. The spawner collects ticks and prints stats every few seconds.
--- Runs until Ctrl+C (CANCEL event).
local function main()
    -- ── Read configuration from env ─────────────────────────
    local num_workers = tonumber(env.get("NUM_WORKERS") or "1000") or 1000
    local tick_min_ms = parse_ms(env.get("TICK_MIN") or "500ms")
    local tick_max_ms = parse_ms(env.get("TICK_MAX") or "3s")
    local stats_interval = env.get("STATS_INTERVAL") or "2s"

    local my_pid = tostring(process.pid())

    logger:info("mass spawn starting", {
        num_workers = num_workers,
        tick_min_ms = tick_min_ms,
        tick_max_ms = tick_max_ms,
        stats_interval = stats_interval,
    })

    -- ── Spawn all workers ──────────────────────────────────
    local spawn_start = time.now()

    for i = 1, num_workers do
        local tick_ms = rand_between(tick_min_ms, tick_max_ms)
        local tick_dur = tostring(tick_ms) .. "ms"

        process.spawn_monitored(
            "app:worker", "app:processes",
            my_pid, i, tick_dur
        )
    end

    local spawn_elapsed = time.now():sub(spawn_start):seconds()
    logger:info("all workers spawned", {
        count = num_workers,
        elapsed_s = spawn_elapsed,
    })

    -- ── State ───────────────────────────────────────────────
    local alive = num_workers
    local total_ticks = 0
    local total_stopped = 0
    local total_failed = 0
    local last_tick_count = 0
    local start_time = time.now()

    -- ── Channels ────────────────────────────────────────────
    local inbox = process.inbox()
    local events = process.events()
    local stats_ticker = time.ticker(stats_interval)
    local stats_ch = stats_ticker:response()

    -- ── Main loop ───────────────────────────────────────────
    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
            stats_ch:case_receive()
        }

        -- ── Lifecycle events (EXIT, CANCEL) ─────────────────
        if r.channel == events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                stats_ticker:stop()
                local elapsed_s = time.now():sub(start_time):seconds()
                local rate = 0
                if elapsed_s > 0 then
                    rate = total_ticks / elapsed_s
                end
                logger:info("shutting down", {
                    workers_spawned = num_workers,
                    still_alive = alive,
                    total_ticks = total_ticks,
                    failed = total_failed,
                    uptime_s = elapsed_s,
                    avg_tick_rate = rate,
                })
                return 0
            elseif event.kind == process.event.EXIT then
                alive = alive - 1
                if event.result.error then
                    total_failed = total_failed + 1
                end
            end

        -- ── Messages from workers ───────────────────────────
        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()
            if topic == "tick" then
                total_ticks = total_ticks + 1
            elseif topic == "stopped" then
                total_stopped = total_stopped + 1
            end

        -- ── Periodic stats ──────────────────────────────────
        elseif r.channel == stats_ch then
            local elapsed_s = time.now():sub(start_time):seconds()
            local ticks_since = total_ticks - last_tick_count
            last_tick_count = total_ticks
            local rate = 0
            if elapsed_s > 0 then
                rate = total_ticks / elapsed_s
            end
            logger:info("stats", {
                alive = alive,
                total_ticks = total_ticks,
                new_ticks = ticks_since,
                failed = total_failed,
                tick_rate = rate,
            })
        end
    end
end

return { main = main }
