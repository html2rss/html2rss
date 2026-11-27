# Selectors

How html2rss extracts feed item fields from a page when a config declares CSS `selectors:`.

## What and when

`Html2rss::Selectors` is the **orchestrator** for the traditional selector path: match item nodes, dispatch each configured field through extractors and optional post-processors, then build `Article` hashes. Prefer this when you know the list markup. Prefer `auto_source:` when you want article guessing without hand-written selectors (see {file:lib/html2rss/auto_source/README.md}).

YAML / MCP wire vocabulary is unchanged (`selectors`, `extractor`, `post_process`). Ruby type names below are the internal API.

## Live flow

1. **Parse** — HTML stays on `Response#parsed_body`. JSON responses are converted once via `JsonXml` into an HTML5 fragment so CSS selectors still run.
2. **Items** — `items.selector` finds each card/node. Omitted, blank, and `Selectors::DEFAULT_ITEMS_SELECTOR` expand to `Html::Navigator::MAIN_ANCHOR_SELECTOR` (permalink anchors). Any other selector, including `a` and `.card`, is used as written. `Config.prepare_defaults` fills that default, with `enhance: true`, only when `selectors:` is present. `enhance: true` fills missing fields through `Selectors::ItemEnhancer` and `AutoSource::ArticleExtractor::Item` (list-card enrichment on the page's SST document; an item they cannot read stays as selected, never dropped); an item with no link of its own gets no `url`, never a `page#id` fragment, and is left out of the feed (`Article#linked?`, the rule auto-source applies too). Enhance fills fields only, never adds items: with an explicit `url` selector it never fills `url` (that selector owns it, so item count and URL set match `enhance: false`); without one it fills `url` only for an item outside page chrome (`Html::Navigator.nokogiri_chrome_scope` is `:chrome` for nav/header/footer items), and with `enhance: true` only the first item carrying a URL is kept. An item needs a resolvable link: configure a `url` selector when the items are not anchors or do not contain one. Enhancement is skipped when title, url, description, published_at, enclosures, and categories are already populated.
3. **Field dispatch** (`Selectors::ItemFields` over `Selectors::FieldPlan`) — for each selectable key (`title`, `url`, `enclosure`, `categories`, …):
   - `FieldPlan` compiles every field once into a `CompiledField` (extractor class + post-processor steps, options validated there) and runs it through one private `run_field` path; `ItemFields` builds the article hash and the anchor `href` `url` default
   - Special keys → `FieldPlan` builds the enclosure hash, fans out guid values, and gathers multi-node categories (category nodes reuse the category field's compiled plan); `ItemFields#article_value` wraps the enclosure into the `enclosures` array
4. **Article** — values land on `Html2rss::Article` (`enclosure` YAML → `enclosures` on the Article).

```text
Selectors (orchestrator)
  └─ ItemEnv
       └─ ItemFields → FieldPlan (field dispatch)
            ├─ Extractors::*#call(**config, xml:) + OPTIONS: [OptionSpec]
            └─ PostProcessors::*#call + StepEnv(base_url:, time_zone:, step_config:, item_env:)
```

## The layers of #call

| Layer | Entrypoint | Role | Inputs / Outputs |
| --- | --- | --- | --- |
| **Strategy execution** | `Extractors::*#call` | Polymorphic instance execution on extractor strategies | Keyword config on `initialize`, returns extracted Object |
| **Strategy execution** | `PostProcessors::*#call` | Polymorphic instance execution on post-processor strategies | Reads `@value` and `@context`, returns transformed Object |
| **Data converter** | `JsonXml.call(object)` | Internal helper converting JSON object to XML string fragment | `(Hash / Array)` → `String` XML fragment |
| **Standalone sanitizer** | `SanitizeHtml.call(html, url)` | Cached helper for description/standalone sanitization | `(html, url)` → sanitized HTML String |

## Extractor vs PostProcessor

| Role | Registry | Verb | Config |
| --- | --- | --- | --- |
| Extractor | `Extractors::NAME_TO_CLASS` | `#call` (class from `FieldPlan`) | YAML `extractor:` + strategy `OPTIONS` |
| Post-processor | `PostProcessors::NAME_TO_CLASS` | `#call` (class from `FieldPlan`) | YAML `post_process:` steps with `name:` + `OPTIONS` |

`Extractors::Attribute` is the HTML-attribute strategy — not the field-dispatch layer (that is `Selectors::FieldPlan`).

## ItemEnv and StepEnv

- **`ItemEnv`** — per-item extraction environment: node, `base_url`, scraper, `time_zone`. Nested selects reuse one env via `#select`.
- **`StepEnv`** — post-processor invocation bag: `step_config` (Hash), `base_url`, `time_zone`, `item_env`. Built by `ItemEnv#context_for(step_config:)`. Distinct from `OptionSpec` (static strategy introspection). Channel URL on Test / MCP is a different field.

## OptionSpec vs SchemaExport

- **`OptionSpec`** — introspection & validation SoT (`for(klass)`, `valid_type?`, `error_message`, `json_type`) with **Ruby-typed** `type:` / `required:`. Strategies own `OPTIONS: [OptionSpec, …]`.
- **`SchemaExport`** — JSON Schema adapter only (`for_extractor`, `for_post_processor`), consuming `OptionSpec#json_type`. `Config::IssueMapper` maps Ruby expectations → JSON via `OptionSpec.json_type_for` so ValidationIssue `expected` wire shape stays stable.

## Constraints

- Class / YAML name stays `Selectors`.
- Strategy verb is `#call`.
- `gsub` rejects a `pattern` longer than 256 characters as written, or whose star-height is greater than 1; `Html2rss.validate` and extraction share that compile.

See also {file:CONTEXT CONTEXT.md} for registry ownership and {Html2rss::Config::SelectorsValidator} for Dry validation of the selectors hash.
