--- Doubles a number.
--- Called via: funcs.call("app:double", 21)
local function call(n)
    return n * 2
end

return { call = call }
