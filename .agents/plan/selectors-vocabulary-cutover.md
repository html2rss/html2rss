# Implementation Plan: selectors-vocabulary-cutover

Intent: inline (synced from Cursor plan `selectors_vocab_cutover_b28cd4e3`)  
Circuit breaker approved: false  
Branch tip: `feat/config-validation-report`

## Status

| Phase | Commit | Gate |
| --- | --- | --- |
| 01 Fold CategoriesExtractor | `8e7911f` | exit 0 |
| 02 Fold OptionContract → Option | `07b09e7` | exit 0 |
| 03 Fold AttributeSelector | `b90c4a0` | exit 0 |
| 04 ItemEnv/StepEnv/base_url | `9674220` | exit 0 |
| 05 OptionSpec/SchemaExport/JsonXml/ExtractorArgs | `f2baeb7` + `b1c44ec` | exit 0 |
| 06 Strategy `#get` → `#call` | `a7b67af` | exit 0 |
| 07 README / CONTEXT / CHANGELOG / make ready | `e7736f4` | `make ready` exit 0 |

## Classification & craft (locked)

- **Classification:** `design`
- **Compat:** Breaking Ruby API only. YAML / MCP wire unchanged. No dual-name aliases. No `FieldSelect`.
- **Folds before renames.** OptionSpec owns Ruby-typed introspection; SchemaExport owns `json_type_for`.

### Locked vocabulary

```text
Selectors (orchestrator; keep class name)
  └─ ItemEnv
       └─ field dispatch private on Selectors
            ├─ Extractors::*#call + ExtractorArgs + OPTIONS: [OptionSpec]
            └─ PostProcessors::*#call + StepEnv(base_url:, time_zone:, options:, item_env:)
OptionSpec.for / .expectation_for
SchemaExport
JsonXml
ValidationReport / ValidationIssue
```

See Cursor plan for full phase target_files / verification_gates. Do not edit the Cursor plan file.
