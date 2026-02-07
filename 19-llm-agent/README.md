# LLM Agent — Text Generation with `wippy/llm`

A CLI process that sends prompts to an LLM and prints responses. Demonstrates
the [wippy/llm](https://hub.wippy.ai/wippy/llm) component with the prompt builder, multi-turn conversations, and
registry-based model configuration.

## Architecture

```
Terminal Host (app:terminal)
└── Process (app:cli)
    ├── .env file → API key (OpenAI or Anthropic)
    ├── registry  → model config (temperature, max_tokens, provider)
    ├── llm.generate(string)                   →  simple generation
    ├── prompt.new():add_system():add_user()   →  prompt builder
    ├── multi-turn conversation                →  3 turns of context
    └── return 0

Dependency: wippy/llm
  └── Provides: llm, prompt libraries
      └── Calls: OpenAI API or Anthropic API
```

## Project Structure

```
19-llm-agent/
├── .env            # API key (OPENAI_API_KEY or ANTHROPIC_API_KEY)
├── wippy.lock
└── src/
    ├── _index.yaml # Registry: dependency, model, env vars, CLI process
    └── cli.lua     # main() → 3 generation examples
```

## Registry Entries

| Entry                   | Kind               | Purpose                                      |
|-------------------------|--------------------|----------------------------------------------|
| `app:__dependency.llm`  | `ns.dependency`    | Pulls in `wippy/llm` component               |
| `app:terminal`          | `terminal.host`    | Terminal host (provides stdout)              |
| `app:processes`         | `process.host`     | Process host (for LLM internals)             |
| `app:file_env`          | `env.storage.file` | File-based env storage (`.env`)              |
| `app:openai_api_key`    | `env.variable`     | OPENAI_API_KEY from `.env`                   |
| `app:anthropic_api_key` | `env.variable`     | ANTHROPIC_API_KEY from `.env`                |
| `app:gpt_4o_mini`       | `registry.entry`   | Model: gpt-4o-mini (temperature, max_tokens) |
| `app:cli`               | `process.lua`      | CLI agent process                            |

## Setup

```bash
cd examples/19-llm-agent
wippy init
wippy install
```

Add your API key to `.env`:

```
OPENAI_API_KEY=sk-...
```

## Running

```bash
wippy run -x app:cli
```

**Expected Output:**

```
=== LLM Agent ===

Model: gpt-4o-mini

── Simple Generation ──
Prompt: "Say hello world in 3 different programming languages."

Response:
Here are "Hello, World!" programs in three languages:

**Python:** `print("Hello, World!")`
**Lua:** `print("Hello, World!")`
**JavaScript:** `console.log("Hello, World!");`

Tokens: 17 prompt + 114 completion = 131 total

── Prompt Builder ──
System: "You are a concise assistant. Reply in one sentence only."
User:   "What is the actor model in concurrent programming?"

Response:
The actor model is a concurrency paradigm where independent "actors" communicate
exclusively through asynchronous message passing, each maintaining private state.

── Multi-Turn Conversation ──
(3 messages of context + follow-up question)

Response:
Array: `local a = {10, 20, 30}`
Dictionary: `local d = {name = "Lua", year = 1993}`
Object: `local obj = {greet = function(self) return "Hi, " .. self.name end, name = "World"}`
Module: `local M = {version = "1.0", run = function() print("running") end}`

Done!
```

## Key Concepts

- **Registry-based model config** — model options (temperature, max_tokens, provider, capabilities) are declared as
  a `registry.entry` with `meta.type: llm.model`. Code only passes `{model = "gpt-4o-mini"}` — the registry handles
  the rest. To change settings, edit `_index.yaml`, not the Lua code.

- **File-based secrets** — API keys live in `.env` (loaded via `env.storage.file`). Keeps secrets out of command-line
  history and version control. The file is auto-created on first run.

- **`llm` and `prompt` are libraries** — imported via `imports:` (not `modules:`). They come from the `wippy/llm`
  dependency as `wippy.llm:llm` and `wippy.llm:prompt`.

- **`llm.generate(input, options)`** — accepts a plain string or a prompt builder. Returns
  `{result, tokens, finish_reason}` or `nil, error`. Token usage includes `prompt_tokens`, `completion_tokens`,
  `total_tokens`.

- **`prompt.new()`** — fluent builder for structured prompts. Chain `:add_system()`, `:add_user()`,
  `:add_assistant()` for multi-turn conversations.

- **Auto-detect provider** — if `OPENAI_API_KEY` is set, uses `gpt-4o-mini`. If only `ANTHROPIC_API_KEY` is set,
  falls back to `claude-sonnet`.

- **`ns.dependency` parameters** — `wippy/llm` requires `env_storage` (where to find API keys) and `process_host`
  (for internal processes). Both are wired in the dependency declaration.

## Adding More Models

Register additional models in `_index.yaml`:

```yaml
- name: gpt_4o
  kind: registry.entry
  meta:
    type: llm.model
    name: gpt-4o
    title: GPT-4o
    class: [ smart, chat ]
    capabilities: [ generate, tool_use, structured_output, vision ]
    priority: 200
  providers:
    - id: wippy.llm.openai:provider
      provider_model: gpt-4o
      options:
        temperature: 0.7
        max_tokens: 1024
```

Then use in code: `llm.generate("Hello", {model = "gpt-4o"})`.

## What's Next

The `wippy/llm` component also supports:

- **Tool calling** — define tools with JSON schemas, handle `result.tool_calls`
- **Structured output** — `llm.structured_output(schema, prompt, options)` for typed responses
- **Streaming** — `stream = {reply_to = ..., topic = ...}` for real-time token delivery
- **Embeddings** — `llm.embed(text, options)` for vector representations
- **Multi-modal** — `prompt.image()` and `prompt.image_base64()` for vision models
- **Model classes** — `llm.generate("Hi", {model = "class:fast"})` picks the highest-priority model in a class
