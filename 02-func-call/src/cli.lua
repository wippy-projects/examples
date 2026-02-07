local io = require("io")
local funcs = require("funcs")

--- Demonstrates calling registered functions via funcs.call().
--- Functions are stateless — call, get result, done.
---
--- Run: wippy run -x app:cli
local function main(): integer
    io.print("=== Function Calls ===")
    io.print("")

    -- Call a function that doubles a number
    local result, err = funcs.call("app:double", 21)
    if err then
        io.print("Error: " .. tostring(err))
        return 1
    end
    io.print("double(21) = " .. tostring(result))

    -- Call a function that greets by name
    local greeting, err = funcs.call("app:greet", "Alice")
    if err then
        io.print("Error: " .. tostring(err))
        return 1
    end
    io.print("greet('Alice') = " .. greeting)

    -- Call multiple times
    io.print("")
    io.print("Calling double() in a loop:")
    for i = 1, 5 do
        local val, err = funcs.call("app:double", i)
        io.print("  double(" .. i .. ") = " .. tostring(val))
    end

    io.print("")
    io.print("Functions are stateless. Each call is independent.")
    return 0
end

return { main = main }
