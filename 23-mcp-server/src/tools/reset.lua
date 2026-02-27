local function call(arguments)
    local target = arguments.target or "cache"
    return "Reset completed for: " .. target
end

return { call = call }
