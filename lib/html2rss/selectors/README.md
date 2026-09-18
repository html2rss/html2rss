# Selectors

How html2rss extracts feed item fields from a page when a config declares CSS `selectors:`.

## What and when

`Html2rss::Selectors` is the **orchestrator** for the traditional selector path: match item nodes, dispatch each configured field through extractors and optional post-processors, then build `Article` hashes. Prefer this when you know the list markup. Prefer `auto_source:` when you want article guessing without hand-written selectors (see {file:lib/html2rss/auto_source/README.md}).

YAML / MCP wire vocabulary is unchanged (`selectors`, `extractor`, `post_process`). Ruby type names below are the internal API.

## Live flow

1. **Parse** — HTML stays on `Response#parsed_body`. JSON responses are converted once via `JsonXml` into an HTML5 fragment so CSS selectors still run.
2. **Items** — `items.selector` finds each card/node. Optional `enhance: true` fills missing fields via `Html::ArticleExtractor` (list-card enrichment).
3. **Field dispatch** (private on `Selectors`) — for each selectable key (`title`, `url`, `enclosure`, `categories`, …):
   - Regular fields → `Extractors.call` → optional `PostProcessors.call` chain
   - Special keys → enclosure wrap, guid fan-out, multi-node categories
4. **Article** — values land on `Html2rss::Article` (`enclosure` YAML → `enclosures` on the Article).

```text
Selectors (orchestrator)
  └─ ItemEnv
       └─ field dispatch (private)
            ├─ Extractors::*#call + ExtractorArgs + OPTIONS: [OptionSpec]
            └─ PostProcessors::*#call + StepEnv(base_url:, time_zone:, options:, item_env:)
```

## Extractor vs PostProcessor

| Role | Registry | Verb | Config |
| --- | --- | --- | --- |
| Extractor | `Extractors::NAME_TO_CLASS` | `#call` / `Extractors.call` | YAML `extractor:` + strategy `OPTIONS` |
| Post-processor | `PostProcessors::NAME_TO_CLASS` | `#call` / `PostProcessors.call` | YAML `post_process:` steps with `name:` + `OPTIONS` |

`Extractors::Attribute` is the HTML-attribute strategy — not the field-dispatch layer (that is private on `Selectors`).

## ItemEnv and StepEnv

- **`ItemEnv`** — per-item extraction environment: node, `base_url`, scraper, `time_zone`. Nested selects reuse one env via `#select`.
- **`StepEnv`** — post-processor invocation bag: `options`, `base_url`, `time_zone`, `item_env`. Built by `ItemEnv#context_for`.

Do not reintroduce `channel_url` on `StepEnv`. Channel domain / Test / MCP `channel_url` stay separate product surfaces.

## OptionSpec vs SchemaExport

- **`OptionSpec`** — introspection SoT (`for(klass)`, `expectation_for`) with **Ruby-typed** `type:` / `required:`. Strategies own `OPTIONS: [OptionSpec, …]`.
- **`SchemaExport`** — JSON Schema adapter only (`json_type_for`, `for_extractor`, `for_post_processor`). `Config::IssueMapper` maps Ruby expectations → JSON via `SchemaExport.json_type_for` so ValidationIssue `expected` wire shape stays stable.

Runtime extractor args (`ExtractorArgs`, Href `Args`) are distinct from YAML `OPTIONS` keys.

## Constraints

- Keep class / YAML name `Selectors` (wire + historic API).
- Strategy verb is `#call` — no `#get` aliases.
- File gravity after folds is accepted; do not re-extract a public `FieldSelect` for line count alone.

See also {file:CONTEXT CONTEXT.md} for registry ownership and {Html2rss::Config::SelectorsValidator} for Dry validation of the selectors hash.
