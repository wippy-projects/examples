local io = require("io")

--- The simplest Wippy example.
--- A process running on a terminal host with stdout access.
---
--- Run: wippy run -x app:hello
local function main(): integer
    io.print("Hello from Wippy!")
    io.print("My PID: " .. process.pid())
    io.print("")
    io.print("This is a process — the basic unit of computation.")
    io.print("Every piece of code in Wippy runs inside a process.")
    io.print("Each process has its own isolated memory.")
    return 0
end

return { main = main }
