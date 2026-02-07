# 🍺 The Rusty Flagon — A Roguelike Bar Conversation

A console-based roguelike conversation game built with Wippy's actor model and LLM integration.

## Concept

You walk into **The Rusty Flagon**, a fantasy tavern. Each time you sit down, a **randomly generated character** appears next to you — with their own name, race, occupation, personality, drunkenness level, mood, secret, speech style, and quirks.

You can chat with them, try to uncover their secrets, buy them drinks, or just enjoy the atmosphere. Type `/new` to move to another seat and meet someone else.

Every character is unique — traits are randomly combined and sent to an LLM which generates a consistent personality and maintains the conversation in character.

## Architecture

```
┌─────────────┐     messages      ┌─────────────┐
│   CLI        │ ──────────────▶  │   Agent      │
│  (terminal)  │ ◀──────────────  │  (process)   │
│              │     responses    │              │
│  - user I/O  │                  │  - LLM calls │
│  - history   │                  │  - prompt    │
│  - character │                  │    builder   │
│    generator │                  │              │
└─────────────┘                  └─────────────┘
```

- **CLI process** runs on `terminal.host`, handles user input/output, generates random characters, maintains conversation history
- **Agent process** runs on `process.host`, receives generation requests via message passing, calls LLM, returns results

## Setup

1. Set your API key in `.env`:
   ```
   OPENAI_API_KEY=sk-...
   ```

2. Install dependencies (ensure `.wippy/vendor/` has the required modules):
   ```bash
   wippy install
   ```

3. Run:
   ```bash
   wippy run
   ```

## Commands

| Command | Action |
|---------|--------|
| `/new`  | Meet a new random character |
| `/look` | Look at the current character's visible traits |
| `/help` | Show available commands |
| `/quit` | Leave the tavern |

Any other text is sent as dialogue to the character.

## Character Traits

Each character is randomly assembled from pools of:

- **20 names** (Grok the Mild, Elara Nightwhisper, Pip Candlewick...)
- **10 races** (human, dwarf, elf, goblin (reformed), undead (friendly)...)
- **20 occupations** (retired adventurer, potion taste-tester, unlicensed dentist...)
- **18 personalities** (paranoid and conspiratorial, theatrically dramatic...)
- **6 drunkenness levels** (sober → barely conscious)
- **12 moods** (celebrating, hiding from someone, looking for trouble...)
- **15 secrets** (hidden treasure, cursed a goat, pocket full of teeth...)
- **10 speech styles** (nautical terms, flowery language, made-up proverbs...)
- **10 quirks** (fidgets with a coin, talks to empty chair...)

This gives **~11.6 billion** unique character combinations.
