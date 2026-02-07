local http = require("http")
local json = require("json")

--- GET /api/health — simple health check endpoint.
local function handler()
    local res = http.response()
    res:set_status(200)
    res:write_json({status = "ok"})
end

return { handler = handler }
