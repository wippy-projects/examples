--- Cron job functions.
--- Each is a function.lua entry with meta.type = "cron.job".
--- The scheduler discovers them, the worker calls them via funcs.call().

local function heartbeat()
    return "ok"
end

local function cleanup()
    local n = math.random(1, 10)
    return n .. " files removed"
end

local function report()
    local cpu = math.random(10, 95)
    local mem = math.random(30, 80)
    return "cpu=" .. cpu .. "% mem=" .. mem .. "%"
end

local function backup()
    local kb = math.random(100, 500)
    return kb .. "KB written"
end

return {
    heartbeat = heartbeat,
    cleanup = cleanup,
    report = report,
    backup = backup,
}
