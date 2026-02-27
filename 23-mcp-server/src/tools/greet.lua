local function call(arguments)
    local name = arguments.name or "World"
    local style = arguments.style or "casual"

    if style == "formal" then
        return "Good day, " .. name .. ". It is a pleasure to make your acquaintance."
    elseif style == "pirate" then
        return "Ahoy, " .. name .. "! Welcome aboard, matey!"
    else
        return "Hey, " .. name .. "!"
    end
end

return { call = call }
