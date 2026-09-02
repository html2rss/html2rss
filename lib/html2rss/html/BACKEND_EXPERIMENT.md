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
| One parse on Document Path A + one Hydrator call | Met (Phases 1–2) |
| Strict admission fidelity vs nokogiri | **Not met** — same `page_1` drift as Lexbor (69/71/17) |
| Significant auto-source win (>30% wall, >50% alloc) | **Not met** — see §4 after one-parse+hydrate |
| Checkpoint (≥15% auto-source wall + clear alloc drop) | **Partial** — ~−10% wall; alloc ≈ flat / slightly up |

**Interpretation:** One-parse + Hydrator cleared the double-parse / per-node Magnus tax. Auto-source wall improved vs prior rust≈nokogiri, but nested Hash IR still allocates O(nodes) Ruby objects and promotion bars remain unmet. Next leverage is profile-guided (TypedData SST / IR arena / admission fidelity) — not SIMD yet.

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
  scraper parse once → sst::normalize_from_html → nested Hash IR
    → SST::Hydrator (sole Attrs/Node/Index/Document owner)
  thin NativeEngine::{Document,Node} remain CSS/attr ducks only
Sitemap / XML → always Nokogiri (no general XPath in Rust)
```

| Piece | Location |
| --- | --- |
| Extension | `ext/html2rss_parser/` (pure Rust `parse`/`sst`; magnus only under `ruby/`) |
| Hydrate SSOT | `lib/html2rss/sst/hydrator.rb` |
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

Microbench (serialize+reparse Document path vs one normalize):

| Path | page_1 (approx) |
| --- | --- |
| `string_page_1` | ~3.3 ms |
| `parse_then_string_normalize_page_1` (old Document#to_sst) | ~7.2 ms |

### After one-parse + hydrate (Phase 3 remasure)

Auto-source (`spec/perf/baseline-auto-source.md`, 2026-09-02T19:48Z):

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.204234 | 724283 | — | — |
| rust | 0.183354 | 727240 | **−10.2** | **+0.4** |

Suite wall (`spec/perf/baseline-suite-wall.md`): rust **−16.8%** vs nokogiri (`13.051s` vs `15.688s`).

Microbench after Phase 1:

| Path | page_1 (approx) |
| --- | --- |
| `parse_then_from_html_page_1` (Document Path A normalize) | ~3.0 ms |
| `from_html_only_page_1` (walk only) | ~0.65 ms |
| `parse_then_string_normalize_page_1` (legacy double work) | ~6.0 ms |

**Gate honesty:** checkpoint ≥15% auto-source wall missed (−10.2%); alloc did not drop. Profile before touching parked list.

## 5. Next leverage (parked)

Do **not** start until wall/alloc profiles name the next bottleneck:

* Arena string pool / `phf` tag sets (if IR nest build is hot after hydrate)
* Portable SIMD / NEON / `memchr` kernels
* Removing nokolexbor
* TypedData SST / Segmenter rewrite (if Hash IR materialization dominates)
* Custom html5ever `TreeSink` for `page_1` fidelity drift
* `gemspec.extensions` / binary gems

## 6. Promotion criteria (unchanged bar)

1. Zero suite failures under rust (and no silent pending that hides HTML XPath debt).
2. Zero article-count / title drift vs nokogiri on fixtures (especially `page_1.html`).
3. >30% wall and >50% alloc reduction on auto-source vs nokogiri.
4. Packaging story (`rake-compiler-dock` / precompiled gems) before flipping default — **out of scope for this wave**.
