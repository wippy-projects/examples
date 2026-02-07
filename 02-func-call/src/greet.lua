--- Greets a person by name.
--- Called via: funcs.call("app:greet", "Alice")
local function call(name)
    return "Hello, " .. name .. "! Welcome to Wippy."
end

return { call = call }
