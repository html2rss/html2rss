# HTML parser backend experiment

**Branch:** `experiment/html-backend-nokolexbor`  
**Base tip:** `origin/master` @ `657a21c0`  
**Captured:** 2026-09-02 (Ruby 4.0.0)  
**Env switch:** `HTML2RSS_HTML_BACKEND=nokogiri|nokolexbor` (default `nokogiri`)

## Verdict: **no-go for production default** (keep experiment branch / facade)

Nokolexbor wins wall-clock on both the scrape/heuristic path and the full RSpec suite, and the suite is green under both backends after CSS compatibility shims. Do **not** flip the production default yet: Sanitize stays on Nokogiri, XML/XPath/sitemap stay off Lexbor, and auto-source article **counts diverge** on at least one fixture (fidelity risk).

Promote only after a dedicated fidelity pass (same articles / same titles on a curated fixture matrix) and an explicit product decision.

## Suite status

| Backend | Examples | Failures |
| --- | --- | ---: |
| nokogiri (default) | 1882 | 0 |
| nokolexbor | 1882 | 0 |

Commands:

```bash
mise exec -- bundle exec rspec --no-fail-fast
HTML2RSS_HTML_BACKEND=nokolexbor mise exec -- bundle exec rspec --no-fail-fast
```

## Performance numbers

### Scrape / heuristic path (`make perf-baseline`)

Source: [`spec/perf/baseline-auto-source.md`](../../../spec/perf/baseline-auto-source.md)

| Backend | wall_time_s (median) | allocations (median) | wall Δ% | alloc Δ% |
| --- | ---: | ---: | ---: | ---: |
| nokogiri | 0.212662 | 723700 | — | — |
| nokolexbor | 0.186589 | 687253 | **−12.3** | **−5.0** |

Fixtures: `page_1.html`, `multi_link_block.html`, `local_feed_test.html` (warmup 1, runs 5, median).

**Fidelity note:** on `page_1.html`, heuristic/auto-source article counts differ:

| Fixture path | nokogiri (semantic / html / auto) | nokolexbor (semantic / html / auto) |
| --- | --- | --- |
| page_1.html | 65 / 61 / 13 | 69 / 71 / 17 |
| multi_link_block.html | 3 / 3 / 3 | 3 / 3 / 3 |
| local_feed_test.html | 3 / 3 / 3 | 3 / 3 / 3 |

Faster + greener suite is not enough while admission counts move.

### Full RSpec suite (`make perf-suite`)

Source: [`spec/perf/baseline-suite-wall.md`](../../../spec/perf/baseline-suite-wall.md)

| Backend | wall_time_s | examples | failures | exit |
| --- | ---: | ---: | ---: | ---: |
| nokogiri | 18.386 | 1882 | 0 | 0 |
| nokolexbor | 14.415 | 1882 | 0 | 0 |

nokolexbor wall Δ vs nokogiri: **−21.6%** (seed `42`, `--no-fail-fast`).

## What landed

1. **`Html::Document` / `Html::Node` / `Html::Backend`** — domain HTML parse + type checks go through the facade; `Response#parse_html_document` returns `Html::Document`.
2. **`Backend::Nokogiri`** — production default; sole constructor of Nokogiri HTML docs (Sanitize transformers still use Nokogiri nodes).
3. **`Backend::Nokolexbor`** — Lexbor via `nokolexbor` **dev dependency**; selected by env.
4. **`Html::Css.normalize`** — Lexbor gaps: `:first` / `:last`, `:not(:first-child)` / `:not(:last-child)`.
5. **Custom pager** — Lexbor CSS syntax errors fall back to XPath (unsupported pure-XPath still returns nil when XPath fails).
6. **Perf harness** — `bin/heuristic-perf-baseline --backend both`, `make perf-baseline`, `bin/perf-suite` / `make perf-suite`.

## Remaining blockers for “no direct nokogiri”

| Item | Stance |
| --- | --- |
| **sanitize** (+ `WrapImgInA` Nokogiri nodes) | **Keep** — transitive Nokogiri OK |
| Sitemap XML + XPath | Separate XML stack; not Lexbor |
| Spec RSS asserts via `Nokogiri::XML` | Switch to REXML only when dropping direct dep |
| Custom pager pure-XPath | Unsupported / best-effort under Lexbor |
| CSS fidelity (`:has`, other Nokogiri extensions) | Shims cover known suite cases only |
| Auto-source count drift (`page_1.html`) | **Blocker for promote** until explained/accepted |
| Direct gemspec `nokogiri` | Removable only when Nokogiri backend + sanitize path are optional/gone |

## Go / no-go

| Option | Decision |
| --- | --- |
| Keep facade + default nokogiri | **GO** (ship-worthy experiment outcome) |
| Default `HTML2RSS_HTML_BACKEND=nokolexbor` in production | **NO-GO** without fidelity memo + product sign-off |
| Drop direct `nokogiri` gemspec dep | **NO-GO** (sanitize + XML) |
| Archive experiment | Premature — facade is useful either way |

## Reproduce

```bash
make perf-baseline   # writes spec/perf/baseline-auto-source.md
make perf-suite      # writes spec/perf/baseline-suite-wall.md
```
