---
name: Structured validation errors
overview: "Breaking clean cut: Html2rss.validate returns Config::ValidationReport (issues only). Dry stays internal. No errors.to_h dual path. Path-preserving selectors + typed ValidationIssue for GUI/MCP/CLI/Test."
todos:
  - id: phase-01-paths
    content: "Phase 01 — Path-preserve nested SelectorsValidator / Items / Enclosure bubbles"
  - id: phase-02-types
    content: "Phase 02 — ValidationIssue + ValidationReport SoT; validate returns Report; delete Dry duck-compat"
  - id: phase-03-consumers
    content: "Phase 03 — Cut over CLI/MCP/Test to issues only; bump mcp_contract_version; CHANGELOG Breaking"
  - id: phase-04-gate
    content: "Phase 04 — make check / make ready"
isProject: false
---

# Structured config validation errors (clean break)

**Repo:** [`html2rss/`](html2rss/) (core). Intent: inline. Circuit breaker approved: false.

**Parent branch tip:** `refactor/selectors-modernization` @ `4a8929da` (PR [#509](https://github.com/html2rss/html2rss/pull/509); user cited #590 which does not exist in this repo).

**Classification:** `design` (wire boundary + closed codes + kill dual error shapes).  
**Architecture:** refactor-boundaries + refactor-types + deep-modules.  
**Runtime:** `$ruby-dev` (Ruby 3.3+ / Data.define / Set; no Struct duck-compat).  
**Compat:** **None.** Breaking public validate / MCP / Test / CLI error shapes. No legacy `errors.to_h` nest, no parallel `issues`+`errors`, no Dry Result as the public return type.

## Problem

Callers treat `validation.errors.to_h` as the contract. Nested selector paths are flattened to prose under `:selectors`. Dry Message richness (`path`, `predicate`, `input`) never leaves the gem. Parse failures fake Dry via `Config::ValidationResult` — a second shape for the same job.

## Craft decisions (must honor)

1. **Public return type:** `Html2rss.validate` / `Config.validate` / `resolve_and_validate` return **`Config::ValidationReport`** only (`success:` + `issues:` frozen Array of `ValidationIssue`). Dry::Validation::Result never crosses the public boundary.
2. **Delete:** Duck-compat `Config::ValidationResult`. Replace with `ValidationReport` (parse failures are `issues` with `code: :parse`, `path: []` or `[:parse]`).
3. **One wire type — `ValidationIssue`:** `Data.define(:path, :code, :message, :expected, :actual)` with closed `CODES` Set.
4. **Path preservation (internal):** Bubble with `key([*prefix, *error.path])`. Strip `NESTING_KEY` when attaching under `:selectors`.
5. **Consumers:** MCP `issues` only; Test `validation_issues`; CLI Report; bump `MCP_CONTRACT_VERSION`; CHANGELOG Breaking.

## Phases

### Phase 01 — Path-preserve nested Dry bubbles
commit: `fix(config): preserve nested paths when bubbling selector validation errors`

### Phase 02 — Typed Report SoT; validate returns Report
commit: `feat(config)!: return ValidationReport with typed issues from validate`

### Phase 03 — Consumer cutover + contract bump
commit: `feat(mcp)!: validate payload uses issues only; bump contract version`

### Phase 04 — Gate
`make check` (fold into Phase 03 if green — no empty commit)

## Residuals
- web validate endpoint; GUI; PP runtime exceptions → Issue
