local llm = require("llm")
local prompt = require("prompt")
local logger = require("logger")

--- LLM agent process: receives generation requests, calls llm.generate, replies.
--- Runs as a registered service so CLI can find it by name.
local function main()
    local events = process.events()
    local inbox = process.inbox()

    process.registry.register("agent")
    logger:info("agent ready")

    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
        }

        if r.channel == events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                process.registry.unregister("agent")
                logger:info("agent shutting down")
                return 0
            end

        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()
            local data = msg:payload():data()
            local sender = msg:from()

            if topic == "generate" then
                local input = data.prompt
                local system_msg = data.system
                local messages = data.messages

                -- Build prompt from request
                local gen_input = input
                if system_msg or messages then
                    local builder = prompt.new()
                    if system_msg then
                        builder:add_system(system_msg)
                    end
                    if messages then
                        for _, m in ipairs(messages) do
                            if m.role == "user" then
                                builder:add_user(m.content)
                            elseif m.role == "assistant" then
                                builder:add_assistant(m.content)
                            end
                        end
                    else
                        builder:add_user(input)
                    end
                    gen_input = builder
                end

                local result, err = llm.generate(gen_input, {
                    model = "class:fast",
                })

                if err then
                    logger:error("generation failed", { error = tostring(err) })
                    process.send(sender, "result", {
                        error = tostring(err),
                    })
                else
                    process.send(sender, "result", {
                        text = result.result,
                        prompt_tokens = result.tokens.prompt_tokens,
                        completion_tokens = result.tokens.completion_tokens,
                        total_tokens = result.tokens.total_tokens,
                    })
                end
            end
        end
    end
end

return { main = main }
