--- Data function for the chat page template
local function handler(context)
    return {
        title = "The Rusty Flagon",
        ws_url = "ws://localhost:8080/ws/chat",
    }
end

return { handler = handler }
