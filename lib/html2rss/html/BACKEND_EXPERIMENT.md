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
| Suite green under `HTML2RSS_HTML_BACKEND=rust` | Met (1890 ex, 0 fail, 1 pending XPath pager) |
| SST-first short-circuit + golden fixtures | Met |
| One parse on Document Path A + direct Magnus SST | Met (nested Hash IR removed) |
| Path A SST wall+alloc ≤ nokogiri on `page_1` | **Met** — see §4 microbench |
| Strict admission fidelity vs nokogiri | **Not met** — same `page_1` drift as Lexbor (69/71/17) |
| Significant auto-source win (>30% wall, >50% alloc) | **Not met** — out of scope for nokogiri-parity goal |
| Checkpoint (≥15% auto-source wall + clear alloc drop) | **Partial** — wall ~−8%; alloc **−12.5%** (clear drop) |

**Interpretation:** Direct Magnus materialization (cached `Attrs`/`Node`/`Index`/`Document`) cleared the nested Hash IR tax. Path A SST wall/alloc now beat nokogiri Normalizer on `page_1`. Auto-source alloc flipped from flat/+ to a clear drop; wall remains under the 15%/30% bars. Remaining blocker for default is admission fidelity (65/61/13), not materialization cost. SIMD / TypedData Segmenter stay parked.

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
  scraper parse once → sst::normalize_from_html → Magnus Attrs/Node/Index/Document
    (cached RClass at init; no nested Hash IR)
  SST::Hydrator remains for Hash IR unit/debug only
  thin NativeEngine::{Document,Node} remain CSS/attr ducks only
Sitemap / XML → always Nokogiri (no general XPath in Rust)
```

| Piece | Location |
| --- | --- |
| Extension | `ext/html2rss_parser/` (pure Rust `parse`/`sst`; magnus only under `ruby/`) |
| Path A materialize | `ext/html2rss_parser/src/ruby/sst.rs` |
| Hash Hydrator (unit/debug) | `lib/html2rss/sst/hydrator.rb` |
| Lazy load | `Html2rss::Html::NativeEngine` |
| Adapter | `lib/html2rss/html/backend/rust.rb` |
| Perf | `make perf-baseline` / `make perf-suite` (`--backend all`; rust skip + note on LoadError) |
| Microbench | `cargo bench --manifest-path ext/html2rss_parser/Cargo.toml --bench normalize --no-default-features` |

Locked decisions honored: scraper only; SST-first; optional compile; no general XPath; `:rust` under `NativeEngine`; nokogiri default; commit `Cargo.lock`; ignore `target/` and compiled `.so`/`.bundle`.

## 4. Recorded baselines

See:

* `spec/perf/baseline-auto-source.md`
* `spec/perf/baseline-suite-wall.md`

Refresh with `make perf-baseline` and `make perf-suite` after meaningful backend changes.

### Before one-parse + hydrate (Phase 0)

Auto-source rust (2026-09-02 earlier capture): **wall −0.3% / alloc −2.9%** vs nokogiri (`0.187904s`, `702936` allocs).

### After one-parse + hydrate (pre–direct Magnus)

Auto-source (`2026-09-02T19:48Z`): rust **−10.2% wall / +0.4% alloc** vs nokogiri.

### After direct Magnus materialize (2026-09-02T20:13Z)

Auto-source (`spec/perf/baseline-auto-source.md`):

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.190699 | 724247 | — | — |
| rust | 0.175511 | 633531 | **−8.0** | **−12.5** |

Suite wall (`spec/perf/baseline-suite-wall.md`): last capture rust **−16.8%** vs nokogiri (not refreshed this wave).

Path A SST microbench on `page_1` (Document already parsed → `SST::Normalizer.call`, median of 15):

| Backend | wall_ms | allocations |
| --- | ---: | ---: |
| nokogiri (Ruby Normalizer) | 11.2 | 44336 |
| rust (direct Magnus) | **6.3** | **39168** |

**Gate honesty:** Path A SST wall+alloc ≤ nokogiri **met**. Auto-source alloc clear drop **met**; ≥15% / ≥30% wall bars still **not** met (parity goal does not require them).

## 5. Next leverage (parked)

* Admission fidelity on `page_1` (65/61/13) — active for nokogiri-parity goal
* Portable SIMD / NEON / `memchr` kernels — only after profile names compute bound
* Removing nokolexbor
* TypedData SST / Segmenter rewrite — only if Path A remasure regresses
* Custom html5ever `TreeSink` for parse-shape drift (if normalize-rule diffs are insufficient)
* `gemspec.extensions` / binary gems

## 6. Promotion criteria (unchanged bar)

1. Zero suite failures under rust (and no silent pending that hides HTML XPath debt).
2. Zero article-count / title drift vs nokogiri on fixtures (especially `page_1.html`).
3. >30% wall and >50% alloc reduction on auto-source vs nokogiri.
4. Packaging story (`rake-compiler-dock` / precompiled gems) before flipping default — **out of scope for this wave**.
