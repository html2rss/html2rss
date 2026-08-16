![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![CI](https://github.com/html2rss/html2rss/workflows/lint%20and%20test/badge.svg)](https://github.com/html2rss/html2rss/actions)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites by scraping HTML or JSON content with **CSS selectors** or **auto-detection**.

This gem is the core of the [html2rss-web](https://github.com/html2rss/html2rss-web) application.

Most people looking for a first working feed should start with `html2rss-web`, run it with Docker, and open one of the included feeds from their own instance before moving to custom configs or the gem APIs.

## Documentation

Detailed usage guides, reference docs, and the feed directory live on the project website:

- [Ruby gem documentation](https://html2rss.github.io/ruby-gem)
- [Request strategies](https://html2rss.github.io/ruby-gem/reference/strategy) (`auto` = `faraday` → `botasaurus`; or pin concrete strategies)
- [Selectors & pagination](https://html2rss.github.io/ruby-gem/reference/selectors#paginated-feeds)
- [Web application](https://html2rss.github.io/web-application)
- [Feed directory](https://html2rss.github.io/feed-directory)
- [Contributing guide](https://html2rss.github.io/get-involved/contributing)
- [GitHub Discussions](https://github.com/orgs/html2rss/discussions)
- [Sponsor on GitHub](https://github.com/sponsors/gildesmarais)

Cloud development: [Open in GitHub Codespaces](https://github.com/codespaces/new?repo=html2rss/html2rss) (also covered in the [installation guide](https://html2rss.github.io/ruby-gem/installation)).

## Architecture

1. **Config** — loads and validates configuration (YAML/hash); schema via `html2rss schema` / `schema/html2rss-config.schema.json`
2. **RequestService** — fetches pages (`faraday`, `botasaurus`, or `local_file`)
3. **Selectors** — extracts content via CSS selectors with extractors/post-processors
4. **AutoSource** — auto-detects content (Schema.org, JSON state, semantic HTML, structural patterns)
5. **FeedBuilder** — assembles Article objects and renders feeds (RSS 2.0 / JSON Feed 1.1)

```text
Config -> Request -> Extraction -> Processing -> Building -> Output
```

## Capture API

The `Html2rss.capture` method analyzes any URL and produces a reusable feed config hash with derived CSS selectors. Use it to speed up writing feed configuration files.

```ruby
config = Html2rss.capture('https://example.com/articles')
File.write('my-feed.yml', YAML.dump(Html2rss::HashUtil.deep_stringify_keys(config)))
```

The CLI alias `html2rss capture` prints the generated config as YAML to stdout. See [`docs/capture.md`](docs/capture.md) for detailed documentation.

## MCP Server

html2rss ships with an [MCP](https://modelcontextprotocol.io/) server that exposes gem capabilities as AI-consumable tools, resources, and prompts:

```bash
# Start with stdio transport (default; for Cursor/Claude Desktop)
html2rss mcp

# Start with HTTP transport (binds 127.0.0.1 only — local use)
html2rss mcp --transport http --port 8080
```

HTTP transport needs `rack`, `rackup`, and `webrick` (declared gem dependencies). It listens on `127.0.0.1` only; do not expose it on a public interface without your own auth and Host/Origin controls.

**Strategy note:** MCP `scrape_url` / `capture_config` with `strategy: "auto"` run the FeedPipeline AutoFallback chain (`faraday` → `botasaurus`). `inspect_url` uses Faraday when `auto` (cheap diagnostic); pin `botasaurus` when you need browser rendering for inspect. Botasaurus needs `BOTASAURUS_SCRAPER_URL`.

### Tools

| Name              | When to use                                               |
| ----------------- | --------------------------------------------------------- |
| `scrape_url`      | One-shot articles now (no saved config)                   |
| `inspect_url`     | Diagnose weak scrape/capture (scrapers/SST/segments)      |
| `capture_config`  | Derive a durable feed config (+ quality `_meta`)          |
| `validate_config` | Schema-check a config before apply (`isError` on failure) |
| `apply_config`    | Run a validated config → RSS XML                          |

### Resources

| URI                     | Description                                                     |
| ----------------------- | --------------------------------------------------------------- |
| `html2rss://schema`     | Full JSON Schema for feed configurations                        |
| `html2rss://extractors` | Registered extractor **names** (options live in schema `$defs`) |
| `html2rss://strategies` | Registered request strategy names                               |

### Prompts

| Name                  | Description                                             |
| --------------------- | ------------------------------------------------------- |
| `scrape-webpage`      | Guided scrape → inspect/retry with botasaurus if needed |
| `capture-feed-config` | Guided capture → validate → optional apply              |

The MCP module (`Html2rss::MCP`) lazy-loads the `mcp` gem — no cost when the server is not running.

## Botasaurus scrape API (Docker)

Start the Botasaurus scrape API for JavaScript-rendered pages (this compose file is **not** the MCP server):

```bash
docker compose -f docker-compose.botasaurus.yml up -d
```

Set `BOTASAURUS_SCRAPER_URL` to `http://127.0.0.1:4010` and use strategy `botasaurus` in MCP tools, Capture, or the CLI.

## Request Strategies

| Strategy     | Description                                                                   |
| ------------ | ----------------------------------------------------------------------------- |
| `auto`       | Tries `faraday`, falls back to `botasaurus` (default in gem/CLI/MCP scrape)   |
| `faraday`    | Plain HTTP requests via Faraday                                               |
| `botasaurus` | Puppeteer-backed scraping for JavaScript pages                                |

`inspect_url` keeps Faraday when `auto` for cheap diagnostics. Elsewhere, strategy can be set via CLI (`--strategy`), gem API keyword argument, or feed config `request.strategy`. See the [request strategies docs](https://html2rss.github.io/ruby-gem/reference/strategy) for more details.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
