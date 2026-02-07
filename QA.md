# Wippy Examples — QA Troubleshooting Guide

Common issues encountered when building Wippy examples, how they were diagnosed, and where the answers came from.

---

## Q: Why do all HTTP endpoints return 200 OK with an empty body?

**Symptom:** `curl -sv` shows `HTTP/1.1 200 OK` with `Content-Length: 0`. No JSON body.

**Root Cause:** Method chaining on the response object doesn't work. `res:set_status(200)` does **not** return `res`, so
`:write_json(...)` fails silently.

```lua
-- BROKEN — set_status() doesn't return res
res:set_status(200):write_json({ products = products })

-- FIXED — separate calls
res:set_status(200)
res:write_json({ products = products })
```

**Applies to:** Every handler across all examples (`shop/`, `http-async-task/`, `http-spawn/`).

**Source:** Wippy docs at `home.wj.wippy.ai/llm/search?q=http+response+write_json+set_status` show `set_status` and
`write_json` as separate calls, never chained.

---

## Q: Why does `msg:payload()` return nil fields when accessing table data?

**Symptom:** In the cart process, `data.sku`, `data.title`, `data.price` are all `nil` after
`local data = msg:payload()`. Debug logging shows `type(data)` is `"userdata"` and `tostring(data)` is
`"payload{format=lua/any}"`.

**Root Cause:** `msg:payload()` returns a payload wrapper object, not a raw Lua table. You must call `:data()` on it to
extract the actual table.

```lua
-- BROKEN — payload wrapper, not a table
local data = msg:payload()
print(data.sku)  -- nil

-- FIXED — unwrap with :data()
local data = msg:payload():data()
print(data.sku)  -- "LAPTOP-001"
```

**Source:** Wippy echo-service tutorial at `home.wj.wippy.ai/llm/context?paths=tutorials/echo-service` states: _"
Messages have msg:topic() for the topic string and msg:payload():data() for the payload."_

---

## Q: Why does the cart process receive `reply_to = nil` even though the handler sends `process.pid()`?

**Symptom:** Handler sends `process.send(cart_pid, "get_cart", { reply_to = process.pid() })`. Cart logs show
`reply_to: nil`.

**Root Cause:** `process.pid()` returns a PID **userdata object**. Userdata does not survive serialization through
`process.send()` — it arrives as `nil` on the other side.

```lua
-- BROKEN — PID userdata doesn't serialize
process.send(cart_pid, "get_cart", { reply_to = process.pid() })

-- FIXED — convert to string first
process.send(cart_pid, "get_cart", { reply_to = tostring(process.pid()) })
```

**Better alternative:** Use `msg:from()` on the receiving side, which returns the sender's PID as a string
automatically:

```lua
-- In the cart process:
local sender = msg:from()  -- "{app:get_cart|0x00007}" (string)
process.send(sender, "cart_response", reply_data)
```

**Source:** Diagnosed by adding `logger:info` calls with `tostring(process.pid())` in the handler (returned valid PID
like `{app:get_cart|0x00007}`) vs checking the received payload in the cart (showed `nil`). Confirmed by Wippy process
docs that `process.send` destination accepts "string (PID or registered name)".

---

## Q: Why does `process.listen("topic")` never receive replies sent via `process.send()`?

**Symptom:** Handler calls `process.listen("cart_response")`, cart calls
`process.send(reply_to, "cart_response", data)`, but `channel.select` always hits the timeout branch.

**Root Cause:** `process.listen(topic)` subscribes to **pubsub/broadcast topics**, not to point-to-point inbox messages.
Messages sent via `process.send()` go to the target's **inbox**.

```lua
-- BROKEN — listen is for pubsub, not inbox
local reply_ch = process.listen("cart_response")
channel.select { reply_ch:case_receive(), timeout:case_receive() }

-- FIXED — use inbox for direct messages
local inbox = process.inbox()
channel.select { inbox:case_receive(), timeout:case_receive() }
```

**Note:** `process.inbox()` does work in `function.lua` (HTTP handler) context, not just `process.lua`.

**Source:** Wippy process docs at `home.wj.wippy.ai/llm/context?paths=lua/core/process` describe `process.inbox()` as
receiving "Message objects from @inbox topic" while `process.listen(topic)` "subscribes to custom topics" (pubsub).

---

## Q: Why does `registry.find({kind = "registry.entry"})` log a warning?

**Symptom:** `WARN finder metadata field must use 'meta.' prefix {"field": "kind", "use_instead": "meta.kind"}`.

**Root Cause:** `registry.find()` filter fields match against entry **metadata**. Passing `kind` without a prefix is
ambiguous. Use `meta.*` fields for filtering.

```lua
-- WARNING — kind treated as metadata field
local entries = registry.find({ kind = "registry.entry" })

-- FIXED — filter by metadata directly
local entries = registry.find({ ["meta.type"] = "product" })
```

This is also more efficient: instead of fetching all `registry.entry` kinds and filtering in Lua, you query exactly the
entries you need.

**Source:** Wippy registry docs at `home.wj.wippy.ai/llm/context?paths=lua/core/registry` state: _"Filter fields match
against entry metadata."_ The runtime warning message itself suggests `meta.kind`.

---

## Q: Does `process.pid()` work inside `function.lua` (HTTP handler) context?

**Answer:** Yes. It returns a valid PID like `{app:handler_name|0x00007}`. The function handler runs with its own
process identity. Other process globals also work: `process.inbox()`, `process.send()`, `process.spawn()`,
`process.registry.lookup()`.

**Source:** Confirmed experimentally — `logger:info("pid", { pid = tostring(process.pid()) })` inside a `function.lua`
handler logs a valid PID.

---

## Q: How does the request-reply pattern work between an HTTP handler and a process?

**Complete working pattern:**

```lua
-- HTTP handler (function.lua):
local inbox = process.inbox()
process.send(target_pid, "request_topic", {
    reply_to = tostring(process.pid())
})
local timeout = time.after("3s")
local r = channel.select {
    inbox:case_receive(),
    timeout:case_receive()
}
if r.channel == timeout then
    -- handle timeout
end
local response = r.value:payload():data()

-- Target process (process.lua):
local msg = r.value  -- from inbox channel.select
local data = msg:payload():data()
local reply_to = data.reply_to or tostring(msg:from())
process.send(reply_to, "response_topic", { ... })
```

**Key points:**

1. Use `process.inbox()` (not `process.listen`) for receiving replies
2. Send PID as `tostring(process.pid())`, not raw PID object
3. Prefer `msg:from()` for reply routing (automatic, no serialization issues)
4. Always unwrap payloads with `:payload():data()`
5. Use `time.after("Ns")` with `channel.select` for timeouts

---

## Q: How do events differ from process messages?

| Aspect      | Process Messages                           | Events                                       |
|-------------|--------------------------------------------|----------------------------------------------|
| Send        | `process.send(pid, topic, data)`           | `events.send(topic, event_type, path, data)` |
| Receive     | `process.inbox()` → `msg:payload():data()` | `events.subscribe()` → `evt.data`            |
| Data access | Method chain: `:payload():data()`          | Dot notation: `evt.data`                     |
| Routing     | Point-to-point (specific PID)              | Pub/sub (all subscribers)                    |
| Use case    | Request-reply between handler and process  | Broadcast notifications (delivery, email)    |

---

## Q: Why does `msg:payload()` work without `:data()` in spawned process context?

**Answer:** It doesn't — it silently fails. In the `03-ping-pong` example, `msg:payload().sender` returned `nil`
instead of the PID string, causing `process.send(nil, ...)` to silently drop messages. The pinger would timeout waiting
for pong, then send "done" — making it *look* like things worked (both processes exited) but the actual ping/pong
exchange never happened.

**Diagnosis:** The exit order revealed the bug. With the broken code, ponger exited first (idle, then got "done").
After fixing to `msg:payload():data()`, pinger exited first (completed 5 rounds), confirming the exchange worked.

**Rule:** Always use `msg:payload():data()` in **every** context — `function.lua`, `process.lua`, spawned processes.
There are no exceptions.
