# Tree-sitter Call Graph — Parsing Code with the `treesitter` Module

An HTTP service that uses Wippy's tree-sitter integration to parse source code, extract function
definitions and call relationships, and render interactive call graphs using Graphviz (viz.js).

Languages are **registry-driven** — sample directories are discovered via `meta.sample` metadata on
`fs.directory` entries. To add a new language, add an entry to `_index.yaml` with the right metadata.

The HTML page is rendered server-side using **Jet templates** via the `wippy/views` module, with
template inheritance (layout + page) and a data function that pre-populates languages.

## Architecture

```
Browser → GET /              → renderer.render() → Jet template → HTML page
       → GET /api/languages  → registry.find() → JSON language list
       → GET /api/graph      → tree-sitter parse → DOT graph text
       → GET /api/files      → fs.directory scan → JSON file list

Templates:
  layout.jet   → base HTML structure (title, styles, body, scripts yield points)
  page.jet     → extends layout, contains the viewer UI + JS

Data flow:
  renderer.render("app:viewer") → calls data_func (page_data.lua)
    → parser.list_languages() → {title, languages}
    → Jet template receives data.title, data.languages
    → {{ range data.languages }} pre-populates <select> and JS array

parser.lua (library):
  1. registry.find({["meta.sample_lang"] = lang}) → resolve volume ID + extension
  2. fs.get(vol_id) → vol:readdir() → list source files
  3. treesitter.parse(lang, code) → AST root node
  4. treesitter.query(lang, pattern) → captures (defs + calls)
  5. Walk parent nodes → find enclosing function for each call
  6. Render DOT with subgraph clusters per file
```

## Adding a New Language

Add an `fs.directory` entry with sample metadata to `_index.yaml`:

```yaml
  - name: go_samples
    kind: fs.directory
    directory: ./src/samples/go
    meta:
      sample: "true"
      sample_lang: go           # tree-sitter language name
      sample_ext: go            # file extension to filter
      sample_label: "Go (Web Server)"  # dropdown display name
```

Then add tree-sitter query patterns to `parser.lua` and place sample files in the directory.
The language will appear automatically in the UI dropdown via `/api/languages`.

## Per-File Graph Types

Clicking a file in the sidebar shows three graph views:

| Tab                | Description                                                       |
|--------------------|-------------------------------------------------------------------|
| **Call Graph**     | Internal function calls within the file                           |
| **Structure**      | Classes as UML record nodes with methods, standalone functions    |
| **External Calls** | Cross-file edges: outgoing calls (purple), incoming calls (green) |

## Project Structure

```
17-treesitter/
├── wippy.lock
├── test.http
└── src/
    ├── _index.yaml
    ├── parser.lua                  # Shared library: registry + extraction + DOT
    ├── templates/
    │   ├── layout.jet              # Base HTML layout (yield points)
    │   └── page.jet                # Viewer page (extends layout)
    ├── data/
    │   └── page_data.lua           # Data function: loads languages
    ├── samples/
    │   ├── php/                    # 10 PHP files (MVC app)
    │   └── python/                 # 10 Python files (data pipeline)
    └── handlers/
        ├── page.lua                # GET / → renderer.render() → HTML
        ├── graph.lua               # GET /api/graph → DOT
        ├── files.lua               # GET /api/files → JSON
        └── languages.lua           # GET /api/languages → JSON
```

## Running

```bash
cd examples/17-treesitter
wippy init
wippy run
# Open http://localhost:8080 in a browser
```

## Testing

```bash
# HTML viewer (rendered via Jet template)
curl http://localhost:8080/

# List registered languages
curl http://localhost:8080/api/languages

# List source files
curl http://localhost:8080/api/files?lang=php

# Full project call graph
curl http://localhost:8080/api/graph?lang=php

# Per-file graphs
curl "http://localhost:8080/api/graph?lang=php&file=Router.php"
curl "http://localhost:8080/api/graph?lang=php&file=Controllers/UserController.php&type=structure"
curl "http://localhost:8080/api/graph?lang=python&file=core/pipeline.py&type=external"
```

## Views Module

This example uses `wippy/views` for server-side HTML rendering:

| Entry       | Kind            | Purpose                                                   |
|-------------|-----------------|-----------------------------------------------------------|
| `views`     | `ns.dependency` | Installs the views component (`wippy/views`)              |
| `templates` | `template.set`  | Groups Jet templates together                             |
| `layout`    | `template.jet`  | Base HTML layout with yield points                        |
| `viewer`    | `template.jet`  | Page template with `data_func` and `meta.type: view.page` |
| `page_data` | `function.lua`  | Data function that loads languages for the template       |

### Template Inheritance

`layout.jet` defines yield points: `title()`, `styles()`, `body()`, `scripts()`.
`page.jet` extends layout and fills each block with the viewer UI content.

### Data Functions

The `page_data` function receives a context with `params` and `query`, and returns data
that becomes available in the template as `data.*`:

```lua
local function handler(context)
    return {
        title = "Tree-sitter Call Graph",
        languages = parser.list_languages(),
    }
end
```

In the template: `{{ data.title }}`, `{{ range data.languages }}`.

## Registry Metadata

| Meta Field            | Purpose                                          |
|-----------------------|--------------------------------------------------|
| `meta.sample: "true"` | Discovery marker for language entries            |
| `meta.sample_lang`    | Tree-sitter language name (e.g. `php`, `python`) |
| `meta.sample_ext`     | File extension to filter (e.g. `php`, `py`)      |
| `meta.sample_label`   | Human-readable label for UI dropdown             |

## Key Concepts

- **`wippy/views`** — views module with renderer, page registry, template engine
- **`template.set`** + **`template.jet`** — Jet template system with inheritance
- **`renderer.render(page_id, route_params, query_params)`** — renders a page with its data function
- **`data_func`** — function called by renderer to load data for the template
- **`registry.find({["meta.sample_lang"] = lang})`** — discover sample volumes by metadata
- **`treesitter.parse(lang, code)`** — parse source code into a concrete syntax tree
- **`treesitter.query(lang, pattern)`** — create S-expression pattern queries
- **`query:captures(root, code)`** — run query against tree, returns `{name, text, node}` items
- **`node:parent()`** — walk up the AST to find enclosing function scope
- **`node:child_by_field_name("name")`** — access named fields in grammar nodes
- **`fs.directory`** entries + `fs.get()` — read sample files from disk volumes
- **`library.lua`** + `imports:` — shared code between handlers

## Wippy Documentation

- Views module: https://home.wj.wippy.ai/en/lua/web/views
- Tree-sitter module: https://home.wj.wippy.ai/en/lua/text/treesitter
- Filesystem module: https://home.wj.wippy.ai/en/lua/storage/filesystem
- Registry module: https://home.wj.wippy.ai/en/lua/runtime/registry
- HTTP service guide: https://home.wj.wippy.ai/en/guides/configuration
