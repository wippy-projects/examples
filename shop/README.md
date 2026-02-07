# Shop — Actor-Per-User Cart with Event-Driven Checkout

A shopping cart service demonstrating core Wippy patterns: **process-per-user** state management, **registry as product
catalog**, **message-passing** for cart operations, and **event bus** for loosely-coupled order processing.

## Architecture

```
                              Registry
                         ┌──────────────────┐
                         │  product.laptop   │
                         │  product.keyboard │
                         │  product.mouse    │
                         │  ...              │
                         └──────────────────┘

HTTP Handlers                Cart Processes (per user)           Background Services
┌─────────────┐         ┌────────────────────────┐         ┌─────────────────────┐
│ GET /products│─ find ──│                        │         │  delivery (service)  │
│ POST /cart   │─ spawn ─│  cart:alice [PID 1]    │         │  subscribes to       │
│ GET  /cart   │─ msg ───│  cart:bob   [PID 2]    │── event ──▶ "shop.order.checkout" │
│ POST /checkout│─ msg ──│  cart:carol [PID 3]    │         ├─────────────────────┤
└─────────────┘         │  ...                   │── event ──▶ notifier (service)  │
                         └────────────────────────┘         │  subscribes to       │
                           │ on checkout: return 0          │  "shop.order.checkout" │
                           │ process dies, memory freed     └─────────────────────┘
```

## Key Concepts Demonstrated

1. **Products as registry entries** — catalog stored in registry with `meta.type: product`, queried via
   `registry.find()`
2. **Process per user** — each user gets a dedicated cart actor, registered by name (`cart:{user_id}`), holding state in
   local memory
3. **Message passing** — HTTP handlers communicate with cart processes via `process.send()` and request/reply pattern
4. **Event bus** — on checkout, cart emits `events.send("shop", "order.checkout", ...)`, two independent services react
5. **Process lifecycle** — cart process exits after checkout (`return 0`), freeing memory. New session = new process

## Project Structure

```
shop/
├── wippy.lock
├── k6.js                        # Load test (gentle shopping simulation)
├── test.http                     # Manual test requests
└── src/
    ├── _index.yaml               # Registry: products, processes, HTTP, services
    ├── cart.lua                  # Cart actor (per user)
    ├── delivery.lua              # Delivery service (listens to events)
    ├── notifier.lua              # Email notifier (listens to events)
    └── handlers/
        ├── products.lua          # GET  /api/products
        ├── cart_add.lua          # POST /api/cart/{user_id}/items
        ├── cart_get.lua          # GET  /api/cart/{user_id}
        └── cart_checkout.lua     # POST /api/cart/{user_id}/checkout
```

## Registry Entries

### Infrastructure

| Entry           | Kind           | Purpose                   |
|-----------------|----------------|---------------------------|
| `app:processes` | `process.host` | Process host (8 workers)  |
| `app:gateway`   | `http.service` | HTTP server on `:8080`    |
| `app:router`    | `http.router`  | Router with `/api` prefix |

### Products (registry data)

| Entry                    | Kind             | SKU        | Price     |
|--------------------------|------------------|------------|-----------|
| `app:product.laptop`     | `registry.entry` | LAPTOP-001 | $1,499.99 |
| `app:product.keyboard`   | `registry.entry` | KB-002     | $149.99   |
| `app:product.mouse`      | `registry.entry` | MOUSE-003  | $79.99    |
| `app:product.monitor`    | `registry.entry` | MON-004    | $599.99   |
| `app:product.headphones` | `registry.entry` | HP-005     | $299.99   |

### Processes & Services

| Entry          | Kind              | Purpose                                  |
|----------------|-------------------|------------------------------------------|
| `app:cart`     | `process.lua`     | Cart actor definition (spawned per user) |
| `app:delivery` | `process.service` | Supervised delivery service              |
| `app:notifier` | `process.service` | Supervised email notifier                |

## API

### GET /api/products

List all products from registry.

**Response `200`:**

```json
{
  "products": [
    {"id": "app:product.laptop", "title": "Laptop Pro 16", "sku": "LAPTOP-001", "price": 1499.99, "stock": 50},
    ...
  ]
}
```

### POST /api/cart/{user_id}/items

Add item to cart. Spawns a cart process for the user if one doesn't exist.

**Request:**

```json
{"sku": "LAPTOP-001", "quantity": 1}
```

**Response `200`:**

```json
{
  "status": "added",
  "user_id": "alice",
  "item": {"sku": "LAPTOP-001", "title": "Laptop Pro 16", "price": 1499.99, "quantity": 1}
}
```

### GET /api/cart/{user_id}

Get cart contents. Sends message to cart process and waits for reply (3s timeout).

**Response `200`:**

```json
{
  "user_id": "alice",
  "items": [
    {"sku": "LAPTOP-001", "title": "Laptop Pro 16", "price": 1499.99, "quantity": 1},
    {"sku": "KB-002", "title": "Mechanical Keyboard", "price": 149.99, "quantity": 2}
  ],
  "total": 1799.97
}
```

### POST /api/cart/{user_id}/checkout

Checkout the cart. Cart process emits event and exits.

**Response `200`:**

```json
{
  "status": "checked_out",
  "order": {
    "user_id": "alice",
    "items": [...],
    "total": 1799.97,
    "timestamp": 1738880000
  }
}
```

After checkout, the delivery and notifier services log the order processing to stdout.

## Running

```bash
cd examples/shop
wippy run
```

## Testing

### Manual — full shopping flow

```bash
# Browse products
curl http://localhost:8080/api/products

# Alice adds items
curl -X POST http://localhost:8080/api/cart/alice/items -H "Content-Type: application/json" -d '{"sku":"LAPTOP-001"}'
curl -X POST http://localhost:8080/api/cart/alice/items -H "Content-Type: application/json" -d '{"sku":"KB-002","quantity":2}'

# View cart
curl http://localhost:8080/api/cart/alice

# Checkout — watch logs for DELIVERY and EMAIL output
curl -X POST http://localhost:8080/api/cart/alice/checkout

# Cart is gone (process died)
curl http://localhost:8080/api/cart/alice
```

### Load test

```bash
k6 run k6.js
```

## Message Flow

### Add to cart (fire-and-forget)

```
HTTP Handler ──process.send(pid, "add_item", {...})──▶ Cart Process
             ◀── (no reply, 200 returned immediately)
```

### Get cart (request/reply)

```
HTTP Handler ──process.send(pid, "get_cart", {reply_to: self})──▶ Cart Process
             ◀──process.send(handler, "cart_response", {...})────┘
```

### Checkout (request/reply + event)

```
HTTP Handler ──process.send(pid, "checkout", {reply_to: self})──▶ Cart Process
             ◀──process.send(handler, "checkout_response")───────┘
                                                                  │
                                            events.send("shop", "order.checkout", order)
                                                                  │
                                              ┌───────────────────┼───────────────────┐
                                              ▼                                       ▼
                                     Delivery Service                        Notifier Service
                                     (logs packaging)                        (logs email)
```
