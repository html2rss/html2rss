# HTML Parser Backend Experiment

**Branch:** `experiment/html-backend-nokolexbor`  
**Status:** Rust backend landed as **opt-in experiment** (not production default). Nokolexbor remains no-go for default.  
**Env switch:** `HTML2RSS_HTML_BACKEND=nokogiri|nokolexbor|rust` (default `nokogiri`)

## 1. Verdicts

### A. Nokolexbor (Lexbor) — **NO-GO for production default**

* Modest suite/auto-source wall wins; article-count drift on `page_1.html` (Nokogiri 65/61/13 vs Lexbor 69/71/17).
* FFI node wrapping reintroduces GC/dispatch cost; fidelity risk blocks promotion.

### B. Rust (`html2rss_parser` + scraper) — **experiment OK; not ready to default**

| Gate | Status |
| --- | --- |
| Optional compile (`rake compile`, no `gemspec.extensions`) | Met |
| Suite green under `HTML2RSS_HTML_BACKEND=rust` | Met (1887 ex, 0 fail, 1 pending XPath pager) |
| SST-first short-circuit + golden fixtures | Met |
| Strict admission fidelity vs nokogiri | **Not met** — same `page_1` drift as Lexbor (69/71/17) |
| Significant auto-source win (>30% wall, >50% alloc) | **Not met** — ~0% wall / ~−3% alloc vs nokogiri on thin-DOM path |

**Interpretation:** Direct SST construction works; thin CSS DOM still pays Ruby wrapper cost, and html5ever tree shape still drifts admission. Next leverage is batch native extraction / tighter SST admission parity — not more node ducks.

## 2. Suite status

| Backend | Examples | Failures | Notes |
| --- | --- | ---: | --- |
| nokogiri (default) | 1887 | 0 | — |
| nokolexbor | 1887 | 0 | admission drift |
| rust | 1887 | 0 | 1 pending (XPath-only pager); requires `rake compile` |

```bash
mise exec -- bundle exec rake compile   # once per machine / after ext changes
mise exec -- bundle exec rspec --no-fail-fast
HTML2RSS_HTML_BACKEND=rust mise exec -- bundle exec rspec --no-fail-fast
```

Unset sandbox `BUNDLE_PATH` if it points at `cursor-sandbox-cache` (breaks native gems).

## 3. Architecture (landed)

```
Raw HTML → Html::Document.parse → Backend::{Nokogiri|Nokolexbor|Rust}
Rust path:
  scraper parse → pure sst::normalize IR → Magnus SST::Document (short-circuit Normalizer)
               → thin NativeEngine::{Document,Node} (CSS/attr ducks only)
Sitemap / XML → always Nokogiri (no general XPath in Rust)
```

| Piece | Location |
| --- | --- |
| Extension | `ext/html2rss_parser/` (pure Rust `parse`/`sst`; magnus only under `ruby/`) |
| Lazy load | `Html2rss::Html::NativeEngine` |
| Adapter | `lib/html2rss/html/backend/rust.rb` |
| Perf | `make perf-baseline` / `make perf-suite` (`--backend all`; rust skip + note on LoadError) |

Locked decisions honored: scraper only; SST-first; optional compile; no general XPath; `:rust` under `NativeEngine`; nokogiri default; commit `Cargo.lock`; ignore `target/` and compiled `.so`/`.bundle`.

## 4. Recorded baselines

See:

* `spec/perf/baseline-auto-source.md`
* `spec/perf/baseline-suite-wall.md`

Refresh with `make perf-baseline` and `make perf-suite` after meaningful backend changes.

## 5. Promotion criteria (unchanged bar)

1. Zero suite failures under rust (and no silent pending that hides HTML XPath debt).
2. Zero article-count / title drift vs nokogiri on fixtures (especially `page_1.html`).
3. >30% wall and >50% alloc reduction on auto-source vs nokogiri.
4. Packaging story (`rake-compiler-dock` / precompiled gems) before flipping default — **out of scope for this wave**.
