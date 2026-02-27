local function call(arguments)
    local text = arguments.text or ""
    return "Echo: " .. text
end

return { call = call }
