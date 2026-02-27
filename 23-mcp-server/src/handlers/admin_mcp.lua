-- Admin MCP HTTP handler — scoped to "admin" tools
-- Requires Authorization: Bearer <token> header for all requests

local http = require("http")
local json = require("json")
local jsonrpc = require("jsonrpc")
local handler = require("handler")

local ADMIN_TOKEN = "secret-admin-token"

local h = nil
local session_counter = 0

local function new_session_id()
    session_counter = session_counter + 1
    return string.format("admin-%x%x", os.time(), session_counter)
end

local function get_handler()
    if h then return h end
    h = handler.new({
        name = "wippy-mcp-admin",
        version = "0.1.0",
        capabilities = { tools = true, prompts = true },
        scope = "admin"
    })
    return h
end

local function handle_post(req, res)
    local mcp = get_handler()

    local data, parse_err = req:body_json()
    if parse_err or not data or type(data) ~= "table" then
        res:set_status(400)
        return res:write_json({error = "Invalid JSON body"})
    end

    local msg = jsonrpc.classify(data)
    local session_id

    if msg.kind == "request" and msg.method == "initialize" then
        session_id = new_session_id()
        mcp:create_session(session_id)
    else
        session_id = req:header("Mcp-Session-Id")
        if not session_id or not mcp:get_session(session_id) then
            res:set_status(400)
            return res:write_json({error = "Missing or invalid Mcp-Session-Id header"})
        end
    end

    local response = mcp:dispatch(session_id, msg)

    if response then
        if msg.kind == "request" and msg.method == "initialize" then
            res:set_header("Mcp-Session-Id", session_id)
        end
        res:set_header("Content-Type", "application/json")
        res:write(response)
    else
        res:set_status(204)
    end
end

local function handle_delete(req, res)
    local mcp = get_handler()
    local session_id = req:header("Mcp-Session-Id")
    if not session_id then
        res:set_status(400)
        return res:write_json({error = "Missing Mcp-Session-Id header"})
    end
    if not mcp:get_session(session_id) then
        res:set_status(404)
        return res:write_json({error = "Session not found"})
    end
    mcp:delete_session(session_id)
    res:set_status(200)
end

--- Verify Bearer token from Authorization header
local function authenticate(req, res)
    local auth = req:header("Authorization")
    if not auth then
        res:set_status(401)
        res:write_json({error = "Missing Authorization header"})
        return false
    end

    local token = string.match(auth, "^Bearer%s+(.+)$")
    if not token or token ~= ADMIN_TOKEN then
        res:set_status(403)
        res:write_json({error = "Invalid or expired token"})
        return false
    end

    return true
end

local function handler_fn()
    local req = http.request()
    local res = http.response()

    if not authenticate(req, res) then
        return
    end

    local method = req:method()

    if method == "POST" then
        handle_post(req, res)
    elseif method == "DELETE" then
        handle_delete(req, res)
    else
        res:set_status(405)
        res:write_json({error = "Method not allowed"})
    end
end

return { handler = handler_fn }
