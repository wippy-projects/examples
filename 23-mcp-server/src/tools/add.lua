local function call(arguments)
    local a = tonumber(arguments.a) or 0
    local b = tonumber(arguments.b) or 0
    return tostring(a + b)
end

return { call = call }
