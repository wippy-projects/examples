# Registry Graph Visualizer — Interactive Dependency Graphs for Wippy Entries

A dark-themed web interface for visualizing dependency graphs between entries in Wippy's registry.
Uses a three-panel layout (sidebar, DOT source, viz.js graph render) with client-side node
interaction — click nodes to highlight neighbors, find shortest paths between entries, and
filter by kind or namespace.

The core innovation is an extensible **edge rule system** — relationship rules are themselves
registry entries (`registry.entry` with `meta.graph.rule: "true"`), so hub components and users
can declare their own link patterns without modifying the graph builder code.

## Architecture

```
Browser → GET /               → renderer.render() → Jet template → HTML page
       → GET /api/graph       → graph_builder.build_full_dot() → DOT text
       → GET /api/entries     → graph_builder.list_entries() → JSON
       → GET /api/kinds       → graph_builder.list_kinds() → JSON
       → GET /api/namespaces  → graph_builder.list_namespaces() → JSON
       → GET /api/rules       → graph_builder.list_rules() → JSON

Graph Building Pipeline:
  1. registry.snapshot():entries() → all registry entries
  2. registry.find({["meta.graph.rule"] = "true"}) → load edge rules
  3. For each entry, match rules by kind pattern → extract edges
  4. render_dot() → DOT with namespace clusters, kind-colored nodes

Client-side Interaction (no server round-trip):
  - Click node → BFS neighbor traversal → opacity-based highlighting
  - "Find Path" mode → click two nodes → BFS shortest path
  - Neighborhood / Dependencies / Dependents tabs
  - Escape or background click → reset
```

## Edge Rule System

Rules are declared as `registry.entry` entries with `meta.graph.rule: "true"`. Each rule defines:

| Field            | Description                                       |
|------------------|---------------------------------------------------|
| `source_kind`    | Kind pattern to match (`http.endpoint`, `*`)      |
| `field` / `type` | How to extract the target reference               |
| `edge_label`     | Label for the edge in DOT output                  |
| `edge_category`  | Color category (`http`, `runtime`, `queue`, etc.) |

Five extraction types:

| Type          | Description                                  | Example                          |
|---------------|----------------------------------------------|----------------------------------|
| `field`       | Single field reference                       | `http.endpoint → handler`        |
| `map_values`  | All values of a map field                    | `http.router → routes.*`         |
| `array`       | Array of references                          | `process.host → entries[]`       |
| `array_field` | Field from each object in an array           | `queue.consumer → queues[].name` |
| `nested`      | Navigate nested objects to extract reference | `ns.dependency → parameters`     |

Adding a new edge rule is just adding a `registry.entry` to any `_index.yaml` — no code changes.

## API Endpoints

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
curl http://localhost:8090/api/graph

# Filter by kind (supports wildcards)
curl "http://localhost:8090/api/graph?kind=http.*"
curl "http://localhost:8090/api/graph?kind=function.lua"

# Filter by namespace
curl "http://localhost:8090/api/graph?ns=app"

# Focus on entry with depth
curl "http://localhost:8090/api/graph?entry=app:router&depth=2"

# Focus direction: dependencies only or dependents only
curl "http://localhost:8090/api/graph?entry=app:router&dir=out"
curl "http://localhost:8090/api/graph?entry=app:router&dir=in"

# Orphan entries (no incoming edges)
curl "http://localhost:8090/api/graph?orphans=true"

# Combined filters
curl "http://localhost:8090/api/graph?kind=function.lua&ns=app"
```

## UI Features

- **Three-panel layout**: sidebar (entry tree), DOT source, interactive graph
- **Sidebar grouping**: toggle between "By Kind" and "By Namespace" tree views
- **Folder click**: click a kind/namespace folder to filter the graph to that group
- **Node click**: client-side BFS highlights connected nodes with configurable depth
- **Path finding**: "Find Path" button → click two nodes → shortest path highlighted
- **Direction tabs**: Neighborhood / Dependencies / Dependents for focused entry
- **Toolbar filters**: Full Graph, Orphans, kind dropdown, namespace dropdown
- **Legend**: floating panel showing kind colors and edge category colors
- **Export**: Download SVG, Copy DOT to clipboard
- **Keyboard**: Escape resets highlighting and path finding mode

## Project Structure

```
21-registry-graph/
├── wippy.lock
├── test.http
├── README.md
└── src/
    ├── _index.yaml                  # All entries: infra, rules, handlers, templates
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
```

## Running

```bash
cd examples/21-registry-graph
wippy install
wippy run
# Open http://localhost:8090 in a browser
```

## Testing

```bash
# HTML page
curl http://localhost:8090/

# Full DOT graph
curl http://localhost:8090/api/graph

# JSON endpoints
curl http://localhost:8090/api/entries
curl http://localhost:8090/api/kinds
curl http://localhost:8090/api/namespaces
curl http://localhost:8090/api/rules

# Filtered graphs
curl "http://localhost:8090/api/graph?kind=http.*"
curl "http://localhost:8090/api/graph?ns=app"
curl "http://localhost:8090/api/graph?entry=app:router&depth=2"
curl "http://localhost:8090/api/graph?orphans=true"
```

## Key Concepts

- **Edge rules as registry entries** — extensible graph relationships without code changes
- **`registry.snapshot():entries()`** — iterate all registered entries at a point in time
- **`registry.find({["meta.graph.rule"] = "true"})`** — discover rules by metadata
- **`wippy/views`** — server-side Jet template rendering with data functions
- **`library.lua`** + `imports:` — shared graph builder code between handlers
- **Client-side BFS** — interactive node highlighting without server round-trips
- **viz.js** + **svg-pan-zoom** — DOT rendering and graph navigation in the browser

## Wippy Documentation

- Registry module: https://home.wj.wippy.ai/en/lua/runtime/registry
- Views module: https://home.wj.wippy.ai/en/lua/web/views
- HTTP service guide: https://home.wj.wippy.ai/en/guides/configuration
- Entry kinds: https://home.wj.wippy.ai/en/guides/entry-kinds
