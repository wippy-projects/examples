local env = require("env")

--- A function that reads env vars for its configuration.
--- Demonstrates how functions access environment variables.
---
--- Called via: funcs.call("app:greet", name)
local function call(name: string): string
    local app_name = env.get("APP_NAME") or "Wippy"
    local greeting_style = env.get("GREETING_STYLE") or "formal"

    if greeting_style == "casual" then
        return "Hey " .. name .. "! Welcome to " .. app_name .. " 👋"
    end

    return "Hello, " .. name .. ". Welcome to " .. app_name .. "."
end

return { call = call }
