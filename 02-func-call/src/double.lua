--- Doubles a number.
--- Called via: funcs.call("app:double", 21)
local function call(n: number): number
    return n * 2
end

return { call = call }
