local io = require("io")
local time = require("time")

--- Helper: send a request to the agent and wait for reply.
local function ask(request: {prompt: string?, system: string?, messages: {any}?}): string?, string?
    local inbox = process.inbox()
    local timeout = time.after("30s")

    local agent_pid = process.registry.lookup("agent")
    if not agent_pid then
        return nil, "agent not found"
    end
    process.send(agent_pid, "generate", request)

    local r = channel.select {
        inbox:case_receive(),
        timeout:case_receive(),
    }

    if r.channel == timeout then
        return nil, "timeout waiting for agent"
    end

    local data = r.value:payload():data()
    if data.error then
        return nil, tostring(data.error)
    end

    return tostring(data.text), nil
end

--- CLI: sends prompts to the agent process and prints results.
local function main(): integer
    io.print("=== LLM Agent ===")
    io.print("")

    -- ── 1. Simple generation ────────────────────────────────
    io.print("── Simple Generation ──")
    io.print("Prompt: \"Say hello world in 3 different programming languages.\"")
    io.print("")

    local text, err = ask({
        prompt = "Say hello world in 3 different programming languages.",
    })

    if err then
        io.print("Error: " .. err)
        return 1
    end

    io.print("Response:")
    io.print(text)
    io.print("")

    -- ── 2. Prompt builder with system message ───────────────
    io.print("── Prompt Builder ──")
    io.print("System: \"You are a concise assistant. Reply in one sentence only.\"")
    io.print("User:   \"What is the actor model in concurrent programming?\"")
    io.print("")

    local text2, err2 = ask({
        system = "You are a concise assistant. Reply in one sentence only.",
        prompt = "What is the actor model in concurrent programming?",
    })

    if err2 then
        io.print("Error: " .. err2)
        return 1
    end

    io.print("Response:")
    io.print(text2)
    io.print("")

    -- ── 3. Multi-turn conversation ──────────────────────────
    io.print("── Multi-Turn Conversation ──")
    io.print("(3 messages of context + follow-up question)")
    io.print("")

    local text3, err3 = ask({
        system = "You are a Lua programming tutor. Be concise.",
        messages = {
            { role = "user", content = "What is a table in Lua?" },
            { role = "assistant", content = "A table is Lua's only data structure — it works as arrays, dictionaries, objects, and modules all in one." },
            { role = "user", content = "Show me a one-line example of each use." },
        },
    })

    if err3 then
        io.print("Error: " .. err3)
        return 1
    end

    io.print("Response:")
    io.print(text3)
    io.print("")

    io.print("Done!")
    return 0
end

return { main = main }
