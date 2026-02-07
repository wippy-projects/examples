local io = require("io")
local env = require("env")

--- Demonstrates environment variable access in Wippy.
---
--- Run: wippy run -x app:cli
local function main(): integer
    io.print("=== Environment Variables ===")
    io.print("")

    -- ── Reading from different storages ─────────────────────
    io.print("── Reading Variables ──")

    io.print("APP_NAME    = " .. tostring(env.get("APP_NAME")))
    io.print("PORT        = " .. (env.get("PORT") or "8080"))
    io.print("LOG_LEVEL   = " .. (env.get("LOG_LEVEL") or "info"))
    io.print("APP_VERSION = " .. tostring(env.get("APP_VERSION")))
    io.print("GREETING    = " .. tostring(env.get("GREETING_STYLE")))
    io.print("")

    -- ── Writing to memory storage ───────────────────────────
    io.print("── Runtime Override (memory storage) ──")
    env.set("LOG_LEVEL", "debug")
    io.print("LOG_LEVEL   = " .. tostring(env.get("LOG_LEVEL")))
    io.print("")

    -- ── Read-only protection ────────────────────────────────
    io.print("── Read-Only Variable ──")
    local ok, err = env.set("APP_VERSION", "2.0.0")
    if err then
        io.print("Cannot set APP_VERSION: " .. tostring(err))
    else
        io.print("APP_VERSION = " .. tostring(env.get("APP_VERSION")))
    end
    io.print("")

    -- ── List declared variables ─────────────────────────────
    io.print("── All Variables (filtered) ──")
    local known = {"APP_NAME", "PORT", "LOG_LEVEL", "APP_VERSION", "GREETING_STYLE"}
    local vars = env.get_all()
    if vars then
        for _, key in ipairs(known) do
            local val = vars[key]
            io.print("  " .. key .. " = " .. (val or "(not set)"))
        end
    end

    io.print("")
    io.print("Done!")
    return 0
end

return { main = main }
