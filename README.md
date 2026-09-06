![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![CI](https://github.com/html2rss/html2rss/workflows/lint%20and%20test/badge.svg)](https://github.com/html2rss/html2rss/actions)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites by scraping HTML or JSON content with **CSS selectors** or **auto-detection**.

This gem is the core of the [html2rss-web](https://github.com/html2rss/html2rss-web) application.

Most people looking for a first working feed should start with `html2rss-web`, run it with Docker, and open one of the included feeds from their own instance before moving to custom configs or the gem APIs.

## Documentation

Detailed usage guides, reference docs, and the feed directory live on the project website:

- [Ruby gem documentation](https://html2rss.github.io/ruby-gem)
- [Request strategies](https://html2rss.github.io/ruby-gem/reference/strategy) (`auto` = `default` → `botasaurus`; or pin concrete strategies)
- [Selectors & pagination](https://html2rss.github.io/ruby-gem/reference/selectors#paginated-feeds)
- [Web application](https://html2rss.github.io/web-application)
- [Feed directory](https://html2rss.github.io/feed-directory)
- [Contributing guide](https://html2rss.github.io/get-involved/contributing)
- [GitHub Discussions](https://github.com/orgs/html2rss/discussions)
- [Sponsor on GitHub](https://github.com/sponsors/gildesmarais)

Cloud development: [Open in GitHub Codespaces](https://github.com/codespaces/new?repo=html2rss/html2rss) (also covered in the [installation guide](https://html2rss.github.io/ruby-gem/installation)).

## Architecture

1. **Config** — loads and validates configuration (YAML/hash); schema via `html2rss schema` / `schema/html2rss-config.schema.json`
2. **RequestService** — fetches pages (`default` (HTTPX), `botasaurus`, or `local_file`)
3. **Selectors** — extracts content via CSS selectors with extractors/post-processors
4. **AutoSource** — auto-detects content (Schema.org, JSON state, semantic HTML, structural patterns)
5. **FeedBuilder** — assembles Article objects and renders feeds (RSS 2.0 / JSON Feed 1.1)

```text
Config -> Request -> Extraction -> Processing -> Building -> Output
```

## CLI Usage

| Verb     | Job                                                           |
| -------- | ------------------------------------------------------------- |
| inspect  | Cheap diagnostics (final URL, status, alternates, surface)    |
| recon    | Verdict + native feed preference (`BUILD` / `DEFER` / `DROP`) |
| capture  | YAML draft config                                             |
| validate | Schema only                                                   |
| test     | Schema + live extraction (min items)                          |
| apply    | Ship RSS from config or URL                                   |
| scrape   | Articles now (one-shot auto-source)                           |

Golden path: optional **inspect → recon → capture → test → apply**. Side door: **validate**. One-shot: **scrape**.

```bash
# Diagnostics and reconnaissance
html2rss inspect https://example.com/news
html2rss recon https://example.com/news
html2rss recon --file urls.txt --verdict BUILD --url-only

# Composable pipes
html2rss recon --file urls.txt --verdict BUILD --url-only | html2rss capture -
html2rss capture https://example.com/news | html2rss test -

# One-shot articles now
html2rss scrape https://example.com/news
html2rss scrape https://example.com/news --format jsonfeed --explain

# Durable config workflow
html2rss capture https://example.com/news --write feed.yml
html2rss test feed.yml --min-items 5
html2rss apply feed.yml

# Schema validation (side door)
html2rss validate config.yml
html2rss validate "configs/**/*.yml"

# Export JSON Schema
html2rss schema --write schema/html2rss-config.schema.json
```

Historic CLI aliases: `feed` → `apply`, `auto` → `scrape`.

### Inspect output

Inspect follows redirects and reports the landing URL in `final_url`. CLI text shows a `Final:` line **only when** the landing URL differs from what you typed — that line means the redirect succeeded, not that inspect stopped early.

Cross-host redirects (e.g. `https://apex.example/` → `https://www.example/`) set `Host` per hop via HTTPX; html2rss does not pin the entry hostname. When `final_url` differs and status is 4xx, retry on `final_url` or pass the site's canonical hostname. Details: [`lib/html2rss/page_recon/README.md`](lib/html2rss/page_recon/README.md).

## Capture API

`Html2rss.capture` returns a `Capture::CaptureResult`. Use `result.yaml` or `result.config`.

```ruby
result = Html2rss.capture('https://example.com/articles')
File.write('my-feed.yml', result.yaml)
# or: File.write('my-feed.yml', Html2rss::Config.to_yaml(result.config))
```

The CLI alias `html2rss capture` prints the generated config as YAML to stdout. See [`lib/html2rss/capture/README.md`](lib/html2rss/capture/README.md) for detailed documentation.

## MCP Server

html2rss ships with an [MCP](https://modelcontextprotocol.io/) server that exposes gem capabilities as AI-consumable tools, resources, and prompts:

```bash
# Start with stdio transport (default; for Cursor/Claude Desktop)
html2rss mcp

# Start with HTTP transport (binds 127.0.0.1 only — local use)
html2rss mcp --transport http --port 8080
```

stdio uses stdout for JSON-RPC, so the daemon logs to **stderr**. It defaults to `LOG_LEVEL=info` (the gem library default stays `warn`) so a foreground watcher sees the start banner, each tool call, and pipeline fallbacks. Use `LOG_LEVEL=debug` for more detail or `LOG_LEVEL=warn` to quiet it.

HTTP transport needs `rack`, `rackup`, and `webrick` (declared gem dependencies). It listens on `127.0.0.1` only; do not expose it on a public interface without your own auth and Host/Origin controls.

**Strategy note:** MCP `scrape` / `capture` with `strategy: "auto"` run default (HTTPX) → Botasaurus AutoFallback. `inspect` uses default (HTTPX) when `auto` (cheap diagnostic); pin `botasaurus` when you need browser rendering for inspect.

**Tool-call budget:** `scrape` is 1 call (auto already hops). Durable config is `capture` → `test` → `apply` (or `validate` → `test` → `apply` when you already have YAML). Call `inspect` only when scrape/capture is weak or you need recon (final URL, status, https→http, native RSS/Atom).

Cursor / Claude Desktop `mcp.json` must put Botasaurus on the **MCP process** (not only your shell):

```json
{
  "mcpServers": {
    "html2rss": {
      "command": "mise",
      "args": ["exec", "--", "html2rss", "mcp"],
      "env": {
        "BOTASAURUS_SCRAPER_URL": "http://127.0.0.1:4010"
      }
    }
  }
}
```

Read `html2rss://runtime` for `version`, `mcp_contract_version`, `catalog_fingerprint`, `tools`, and `botasaurus_configured` (the scraper URL is never returned). Refresh `tools/list` when `catalog_fingerprint` differs from your cache. Every tool result is a JSON envelope (`ok`, `next_step`, `guidance`, `payload`) in both the text body and `structuredContent`. Follow `next_step` / `guidance`; do not parse scrape text as a raw item array.

Module guide: [`lib/html2rss/mcp/README.md`](lib/html2rss/mcp/README.md).

### Tools

| Name            | When to use                                                                    |
| --------------- | ------------------------------------------------------------------------------ |
| `scrape`        | One-shot articles now (`payload.items`; empty is still success)                |
| `batch_scrape`  | Parallel one-shot scrape across multiple URLs (`urls`, `limit`, `concurrency`) |
| `inspect`       | Weak scrape/capture or recon (final_url, status, scheme_downgrade, feeds)      |
| `batch_inspect` | Parallel diagnostics across multiple URLs (`urls`, `strategy`, `concurrency`)  |
| `recon`         | Verdict + native_feed preference                                               |
| `batch_recon`   | Parallel recon across multiple URLs                                            |
| `capture`       | YAML draft in `payload.yaml`; strive `enhance: true`                           |
| `validate`      | Schema-check a `config` hash XOR `yaml` string (`isError` on failure)          |
| `test`          | Schema + live extraction; `quality_report.enhance_gains` when enhance on; optional `compare_enhance` |
| `apply`         | RSS in `payload.rss`; `isError` when zero items; `quality_report` may include `enhance_gains`          |

### Resources

| URI                     | Description                                                     |
| ----------------------- | --------------------------------------------------------------- |
| `html2rss://schema`     | Full JSON Schema for feed configurations                        |
| `html2rss://extractors` | Registered extractor **names** (options live in schema `$defs`) |
| `html2rss://strategies` | Published MCP strategies (`auto`, `default`, `httpx`, `botasaurus`)      |
| `html2rss://runtime`    | `version`, `mcp_contract_version`, `catalog_fingerprint`, `tools`, `botasaurus_configured` (never the scraper URL) |

### Prompts

| Name                  | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `scrape-webpage`      | One `scrape` call; `inspect` only if weak or recon needed    |
| `capture-feed-config` | Capture YAML → test → apply; catalog rewrite; strive enhance |

The MCP module (`Html2rss::MCP`) lazy-loads the `mcp` gem — no cost when the server is not running.

## Botasaurus scrape API (Docker)

Start the Botasaurus scrape API for JavaScript-rendered pages (this compose file is **not** the MCP server):

```bash
docker compose -f docker-compose.botasaurus.yml up -d
```

Set `BOTASAURUS_SCRAPER_URL` to `http://127.0.0.1:4010` and use strategy `botasaurus` in MCP tools, Capture, or the CLI.

## Request Strategies

| Strategy     | Description                                                                 |
| ------------ | --------------------------------------------------------------------------- |
| `auto`       | Tries `default`, falls back to `botasaurus` (default in gem/CLI/MCP scrape) |
| `default`    | Plain HTTP requests via HTTPX (alias: `httpx`; legacy: `faraday`)           |
| `botasaurus` | Puppeteer-backed scraping for JavaScript pages                              |

`inspect` keeps `default` when `auto` for cheap diagnostics. Elsewhere, strategy can be set via CLI (`--strategy`), gem API keyword argument, or feed config `strategy`. See the [request strategies docs](https://html2rss.github.io/ruby-gem/reference/strategy) for more details.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
