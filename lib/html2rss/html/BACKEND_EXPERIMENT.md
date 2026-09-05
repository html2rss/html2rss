# HTML Parser Backend Experiment

**Branch:** `experiment/html-backend-nokolexbor`  
**Status:** Rust backend landed as **opt-in experiment** (not production default). Nokolexbor remains no-go for default.  
**Env switch:** `HTML2RSS_HTML_BACKEND=nokogiri|nokolexbor|rust` (default `nokogiri`)

## 1. Verdicts

### A. Nokolexbor (Lexbor) — **NO-GO for production default**

* Modest suite/auto-source wall wins; article-count drift on `page_1.html` (Nokogiri 65/61/13 vs Lexbor 69/71/17).
* FFI node wrapping reintroduces GC/dispatch cost; fidelity risk blocks promotion.

### B. Rust (`html2rss_parser` + scraper) — **experiment OK; nokogiri parity met; not ready to default**

| Gate | Status |
| --- | --- |
| Optional compile (`rake compile`, no `gemspec.extensions`) | Met |
| Suite green under `HTML2RSS_HTML_BACKEND=rust` | Met (1890 ex, 0 fail, 1 pending XPath pager) |
| SST-first short-circuit + golden fixtures | Met |
| One parse on Document Path A + direct Magnus SST | Met (nested Hash IR removed) |
| Path A SST wall+alloc ≤ nokogiri on `page_1` | **Met** — ~5.7 ms / 39k vs ~8.8 ms / 44k |
| Strict admission fidelity vs nokogiri | **Met** — `page_1` **65 / 61 / 13** |
| Significant auto-source win (>30% wall, >50% alloc) | **Not met** — out of scope for nokogiri-parity goal |
| Checkpoint (≥15% auto-source wall + clear alloc drop) | **Partial** — wall ~−10%; alloc ~−3% after fidelity mend |

**Interpretation:** Direct Magnus materialization cleared the nested Hash IR tax (Path A SST ≤ nokogiri). Libxml-like list mending (`mend_lists`) fixed html5ever adoption-agency drift so admission matches nokogiri on `page_1`. Promotion bars (>30% / >50%) remain unmet and out of scope; default stays nokogiri. SIMD / TypedData Segmenter stay parked.

## 2. Suite status

| Backend | Examples | Failures | Notes |
| --- | --- | ---: | --- |
| nokogiri (default) | 1890 | 0 | — |
| nokolexbor | 1890 | 0 | admission drift |
| rust | 1890 | 0 | 1 pending (XPath-only pager); requires `rake compile` |

```bash
mise exec -- bundle exec rake compile   # once per machine / after ext changes
mise exec -- bundle exec rspec --no-fail-fast
HTML2RSS_HTML_BACKEND=rust mise exec -- bundle exec rspec --no-fail-fast
```

Unset sandbox `BUNDLE_PATH` if it points at `cursor-sandbox-cache` (breaks native gems).

## 3. Architecture (landed)

```
Raw HTML → Html::Document.parse → Backend::{Nokogiri|Nokolexbor|Rust}
Rust Path A (heuristic SST):
  scraper parse once → sst::normalize_from_html → mend_lists (libxml nest parity)
    → Magnus Attrs/Node/Index/Document (cached RClass; no nested Hash IR)
  SST::Hydrator remains for Hash IR unit/debug only
  thin NativeEngine::{Document,Node} remain CSS/attr ducks only
Sitemap / XML → always Nokogiri (no general XPath in Rust)
```

| Piece | Location |
| --- | --- |
| Extension | `ext/html2rss_parser/` (pure Rust `parse`/`sst`; magnus only under `ruby/`) |
| Path A materialize | `ext/html2rss_parser/src/ruby/sst.rs` |
| List nest mend | `ext/html2rss_parser/src/sst/mend_lists.rs` |
| Hash Hydrator (unit/debug) | `lib/html2rss/sst/hydrator.rb` |
| Lazy load | `Html2rss::Html::NativeEngine` |
| Adapter | `lib/html2rss/html/backend/rust.rb` |
| Perf | `make perf-baseline` / `make perf-suite` |
| Microbench | `cargo bench --manifest-path ext/html2rss_parser/Cargo.toml --bench normalize --no-default-features` |

Locked decisions honored: scraper only; SST-first; optional compile; no general XPath; `:rust` under `NativeEngine`; nokogiri default; commit `Cargo.lock`; ignore `target/` and compiled `.so`/`.bundle`.

## 4. Recorded baselines

See:

* `spec/perf/baseline-auto-source.md`
* `spec/perf/baseline-suite-wall.md`

### After direct Magnus + fidelity mend (2026-09-02T20:28Z remasure)

Auto-source (`spec/perf/baseline-auto-source.md`):

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.185460 | 724257 | — | — |
| rust | 0.166509 | 699283 | **−10.2** | **−3.4** |

`page_1` article counts (rust): **semantic=65, html=61, auto_source=13** (matches nokogiri).

Path A SST microbench on `page_1` (Document already parsed → `SST::Normalizer.call`, median of 15):

| Backend | wall_ms | allocations |
| --- | ---: | ---: |
| nokogiri (Ruby Normalizer) | 8.8 | 44336 |
| rust (direct Magnus + mend) | **5.7** | **38998** |

**Gate honesty:** nokogiri materialization + admission parity **met**. Auto-source >30% / >50% promotion bars **not** met (explicit non-goal).

## 5. Next leverage (parked)

* Portable SIMD / NEON / `memchr` kernels — only after profile names compute bound
* Removing nokolexbor
* TypedData SST / Segmenter rewrite
* Custom html5ever `TreeSink` (mend_lists covers page_1; revisit if other fixtures drift)
* `gemspec.extensions` / binary gems
* Default cutover — blocked on promotion bars + packaging

## 6. Promotion criteria (unchanged bar)

1. Zero suite failures under rust (and no silent pending that hides HTML XPath debt).
2. Zero article-count / title drift vs nokogiri on fixtures (especially `page_1.html`).
3. >30% wall and >50% alloc reduction on auto-source vs nokogiri.
4. Packaging story (`rake-compiler-dock` / precompiled gems) before flipping default — **out of scope for this wave**.
