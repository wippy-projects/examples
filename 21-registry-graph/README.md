# Registry graph visualization

Interactive registry graph visualization with DOT rendering and an extensible edge rule engine.

Designed as a reusable module that plugs into any Wippy application via `ns.dependency` — the package doesn't own any
infrastructure. Your app provides the HTTP router; the package handles everything else: graph building, DOT rendering,
a dark-themed web UI with client-side interaction, and a declarative edge rule system.

<img width="800"  alt="Image" src="https://github.com/user-attachments/assets/60c273c3-5de2-49b1-a7c7-e797b8cbf5bb" />

## Features

- **Interactive web UI** with three-panel layout (sidebar, DOT source, viz.js graph render)
- **Extensible edge rule system** — rules are registry entries, add your own without modifying the package
- **Client-side node interaction** — click to highlight neighbors, find shortest paths, filter by kind/namespace
- **DOT graph API** with filtering by kind, namespace, entry focus with depth, orphan detection
- **Prefix-aware** — mount at any path (`/graph`, `/debug/registry`, etc.)

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  PACKAGE (butschster/registry-graph)                         │
│                                                              │
│  ns.requirements (injected by consumer):                     │
│    ● api_router  → HTTP router for all endpoints and views   │
│                                                              │
│  ns.dependencies:                                            │
│    ● wippy/views → template rendering engine                 │
│                                                              │
│  graph/          Core: ns.definition, edge rules, handlers   │
│                  Templates, graph builder library             │
│                  6 HTTP endpoints, 24 built-in edge rules     │
└──────────────────────────────────────────────────────────────┘
                         ▲
                         │  ns.dependency + parameters
                         │
┌──────────────────────────────────────────────────────────────┐
│  YOUR APP                                                    │
│                                                              │
│  Provides:                                                   │
│    ● http.service + http.router  → api_router                │
│    ● wippy/views  (with api_router wired to your router)     │
└──────────────────────────────────────────────────────────────┘
```

## Installation

### 1. Add the `wippy/views` dependency

The registry-graph package uses `wippy/views` for template rendering. Your app must provide this dependency
with the `api_router` parameter wired to your HTTP router:

```yaml
# src/_index.yaml
version: "1.0"
namespace: app

entries:
  - name: views
    kind: ns.dependency
    component: wippy/views
    version: "*"
    parameters:
      - name: api_router
        value: app:router_http

  - name: gateway
    kind: http.service
    addr: ":8080"
    lifecycle:
      auto_start: true

  - name: router_http
    kind: http.router
    meta:
      server: app:gateway
```

### 2. Create `src/_graph.yaml`

The dependency and its router **must** live in a separate file with `namespace: graph` (matching the package's own
namespace). This is required because endpoint entries resolve their router reference at entry load time — before
`ns.requirement` parameter injection takes place. By defining the router in the package's namespace, the reference
`graph:router` exists when endpoints need it.

```yaml
# src/_graph.yaml
version: "1.0"
namespace: graph

entries:
  - name: dep.graph
    kind: ns.dependency
    component: butschster/registry-graph
    version: "*"
    parameters:
      - name: api_router
        value: graph:router

  # Router must be defined here (in the graph namespace) so that
  # graph endpoints can resolve their meta.router reference.
  - name: router
    kind: http.router
    meta:
      server: app:gateway
    prefix: /graph
```

> **Note:** Ideally you should be able to pass any router (e.g. `app:my_router`) as the `api_router` parameter and
> define everything in your app's namespace. This is a known limitation — `ns.requirement` injection currently happens
> after entry references are resolved. This workaround will be removed once the resolution order is fixed in Wippy.

### 3. Open the graph

Navigate to `http://localhost:8080/graph/` in your browser.

## API Endpoints

All endpoints are relative to the router prefix (e.g. `/graph`).

| Endpoint              | Query Params                                     | Description                   |
|-----------------------|--------------------------------------------------|-------------------------------|
| `GET /`               |                                                  | HTML viewer page              |
| `GET /api/graph`      | `kind`, `ns`, `entry`, `depth`, `dir`, `orphans` | DOT graph text                |
| `GET /api/entries`    |                                                  | All entries (id, kind, ns)    |
| `GET /api/kinds`      |                                                  | Unique kinds with counts      |
| `GET /api/namespaces` |                                                  | Unique namespaces with counts |
| `GET /api/rules`      |                                                  | Active edge rules             |

### Filter Examples

```bash
# Full graph
curl http://localhost:8080/graph/api/graph

# Filter by kind (supports wildcards)
curl "http://localhost:8080/graph/api/graph?kind=http.*"

# Filter by namespace
curl "http://localhost:8080/graph/api/graph?ns=app"

# Focus on entry with depth
curl "http://localhost:8080/graph/api/graph?entry=app:router&depth=2"

# Focus direction: dependencies only or dependents only
curl "http://localhost:8080/graph/api/graph?entry=app:router&dir=out"
curl "http://localhost:8080/graph/api/graph?entry=app:router&dir=in"

# Orphan entries (no incoming edges)
curl "http://localhost:8080/graph/api/graph?orphans=true"
```

## Edge Rule System

Rules are declared as `registry.entry` entries with `meta.graph.rule: "true"`. Each rule defines:

| Field            | Description                                       |
|------------------|---------------------------------------------------|
| `match_kind`     | Kind pattern to match (`http.endpoint`, `*`)      |
| `field` / `type` | How to extract the target reference               |
| `edge_label`     | Label for the edge in DOT output                  |
| `category`       | Color category (`http`, `runtime`, `queue`, etc.) |

Five extraction types:

| Type          | Description                                  | Example                          |
|---------------|----------------------------------------------|----------------------------------|
| `field`       | Single field reference                       | `http.endpoint → handler`        |
| `map_values`  | All values of a map field                    | `http.router → routes.*`         |
| `array`       | Array of references                          | `process.host → entries[]`       |
| `array_field` | Field from each object in an array           | `queue.consumer → queues[].name` |
| `nested`      | Navigate nested objects to extract reference | `ns.dependency → parameters`     |

### Adding Custom Rules

Add edge rules to your own `_index.yaml` — no modification of this package needed. The graph builder discovers
them via `registry.find()`.

```yaml
# Example: show env.variable → storage relationships
- name: rule.env_variable.storage
  kind: registry.entry
  meta:
    graph.rule: "true"
  rule:
    match_kind: "env.variable"
    field: "storage"
    location: "data"
    label: "storage"
    edge_style: "solid"
    category: "storage"
```

### Built-in Rules

The package ships with 24 edge rules covering common Wippy patterns:

| Rule                                  | Match Kind         | Relationship                  |
|---------------------------------------|--------------------|-------------------------------|
| `rule.http_router.server`             | `http.router`      | router → server               |
| `rule.http_endpoint.router`           | `http.endpoint`    | endpoint → router             |
| `rule.http_endpoint.func`             | `http.endpoint`    | endpoint → handler func       |
| `rule.process_service.process`        | `process.service`  | service → process             |
| `rule.process_service.host`           | `process.service`  | service → host                |
| `rule.queue_consumer.queue`           | `queue.consumer`   | consumer → queue              |
| `rule.queue_consumer.func`            | `queue.consumer`   | consumer → handler func       |
| `rule.queue_queue.driver`             | `queue.queue`      | queue → driver                |
| `rule.template_jet.set`               | `template.jet`     | template → set                |
| `rule.template_jet.data_func`         | `template.jet`     | template → data function      |
| `rule.imports`                        | `*.lua`            | imports map values            |
| `rule.depends_on`                     | `*`                | lifecycle.depends_on          |
| `rule.depends_on_root`                | `*`                | root-level depends_on         |
| `rule.ns_dependency.params`           | `ns.dependency`    | dependency → param values     |
| `rule.ns_requirement.targets`         | `ns.requirement`   | requirement → target entries  |
| `rule.ns_requirement.default`         | `ns.requirement`   | requirement → default entry   |
| `rule.env_variable.storage`           | `env.variable`     | variable → storage            |
| `rule.registry_entry.handler`         | `registry.entry`   | entry → handler               |
| `rule.registry_entry.scanner_handler` | `registry.entry`   | entry → scanner handler       |
| `rule.registry_entry.providers`       | `registry.entry`   | entry → providers[].id        |
| `rule.registry_entry.driver`          | `registry.entry`   | entry → driver.id             |
| `rule.registry_entry.driver_options`  | `registry.entry`   | entry → driver.options values |
| `rule.contract_binding.contracts`     | `contract.binding` | binding → contract + methods  |

## UI Features

- **Three-panel layout**: sidebar (entry tree), DOT source, interactive graph
- **Sidebar grouping**: toggle between "By Kind" and "By Namespace" tree views
- **Folder click**: click a kind/namespace folder to filter the graph to that group
- **Node click**: client-side BFS highlights connected nodes with configurable depth
- **Path finding**: "Find Path" button — click two nodes — shortest path highlighted
- **Direction tabs**: Neighborhood / Dependencies / Dependents for focused entry
- **Toolbar filters**: Full Graph, Orphans, kind dropdown, namespace dropdown
- **Legend**: floating panel showing kind colors and edge category colors
- **Export**: Download SVG, Copy DOT to clipboard
- **Keyboard**: Escape resets highlighting and path finding mode

## Project Structure

```
src/                             # Package source (namespace: graph)
├── _index.yaml                  # ns.definition, ns.requirement, rules, handlers, templates
├── graph_builder.lua            # Shared library: graph building + DOT rendering
├── templates/
│   ├── layout.jet               # Base HTML layout (yield points)
│   └── page.jet                 # Dark-themed viewer UI + client-side JS
├── data/
│   └── page_data.lua            # Data function: loads kinds + namespaces
└── handlers/
    ├── page.lua                 # GET / → renderer.render() → HTML
    ├── graph.lua                # GET /api/graph → DOT (with filters)
    ├── entries.lua              # GET /api/entries → JSON
    ├── kinds.lua                # GET /api/kinds → JSON
    ├── namespaces.lua           # GET /api/namespaces → JSON
    └── rules.lua                # GET /api/rules → JSON

dev/                             # Development app (NOT published)
├── _index.yaml                  # app: HTTP server on :8090, wippy/views dependency
└── _graph.yaml                  # graph: router + ns.dependency wiring
```

## Local Development

The `dev/` directory contains a consumer app for local testing. The `wippy.lock` file points to the local `src/`
directory:

```yaml
directories:
  modules: .wippy
  src: ./dev
replacements:
  - from: butschster/registry-graph
    to: ./src
```

To develop locally:

```bash
cd examples/21-registry-graph
wippy install
wippy run
# Open http://localhost:8090/graph/ in a browser
```

## Requirements

The package declares one `ns.requirement` entry that consumers must provide:

| Requirement  | Injects Into                           | Description                             |
|--------------|----------------------------------------|-----------------------------------------|
| `api_router` | `.meta.router` on all 6 HTTP endpoints | HTTP router where endpoints are mounted |

## License

MIT
