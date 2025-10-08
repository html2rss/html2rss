![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![CI](https://github.com/html2rss/html2rss/workflows/lint%20and%20test/badge.svg)](https://github.com/html2rss/html2rss/actions)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites by scraping HTML or JSON content with **CSS selectors** or **auto-detection**.

This gem is the core of the [html2rss-web](https://github.com/html2rss/html2rss-web) application.

## Documentation

Detailed usage guides, reference docs, and the feed directory live on the project website:

- [Ruby gem documentation](https://html2rss.github.io/ruby-gem)
- [Web application](https://html2rss.github.io/web-application)
- [Feed directory](https://html2rss.github.io/feed-directory)
- [Contributing guide](https://html2rss.github.io/get-involved/contributing)
- [GitHub Discussions](https://github.com/orgs/html2rss/discussions)
- [Sponsor on GitHub](https://github.com/sponsors/gildesmarais)

### 💻 Try in Browser

You can develop html2rss directly in your browser using GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=html2rss/html2rss)

The Codespace comes pre-configured with Ruby 3.4 (compatible with Ruby 4.0), all dependencies, and VS Code extensions ready to go!

## 🤝 Contributing

Please see the [contributing guide](https://html2rss.github.io/get-involved/contributing) for details on how to contribute.

## 🏗️ Architecture

### Core Components

1. **Config** - Loads and validates configuration (YAML/hash)
2. **RequestService** - Fetches pages using Faraday or Browserless
3. **Selectors** - Extracts content via CSS selectors with extractors/post-processors
4. **AutoSource** - Auto-detects content using Schema.org, JSON state blobs, semantic HTML, and structural patterns
5. **RssBuilder** - Assembles Article objects and renders RSS 2.0

### Data Flow

```text
Config -> Request -> Extraction -> Processing -> Building -> Output
```

## 🌐 Browserless Strategy Configuration

The Browserless request strategy can execute additional page interactions before the HTML is captured. Configure these options in
your feed under the `request` key:

```yaml
strategy: browserless
request:
  max_redirects: 5
  max_requests: 6
  browserless:
    preload:
      wait_for_network_idle:
        timeout_ms: 5000
      click_selectors:
        - selector: '.load-more'
          max_clicks: 3
          delay_ms: 250
          wait_for_network_idle:
            timeout_ms: 4000
      scroll_down:
        iterations: 5
        delay_ms: 200
        wait_for_network_idle:
          timeout_ms: 3000
```

- **`wait_for_network_idle`** – Waits for the network to become idle before and after preload actions. If no `timeout_ms` is
  provided the default of 5000 ms is used. Browserless exposes this as a timeout
  wait, so html2rss simply pauses the page for the configured milliseconds to let
  pending requests finish.
- **`click_selectors`** – Repeatedly clicks matching elements (e.g. “Load more”) until the element disappears or `max_clicks` is
  reached. Provide per-click `wait_for_network_idle` blocks to avoid racing requests and to stay within Browserless rate limits.
- **`scroll_down`** – Scrolls to the bottom of the page. The loop stops early once the document height stops increasing. Combine
  with `wait_for_network_idle` or `delay_ms` to give JavaScript time to append new content.

Each step increases overall runtime. Browserless sessions have execution limits, so favour conservative values for `max_clicks`,
`iterations`, and timeouts to prevent premature session termination.

### Config schema workflow

The config schema is generated from the runtime `dry-validation` contracts and exported for client-side tooling.

- Ruby API: `Html2rss::Config.json_schema`
- CLI: `html2rss schema`
- CLI options:
  - `html2rss schema --write tmp/html2rss-config.schema.json`
  - `html2rss schema --no-pretty`
- Runtime validation API: `Html2rss::Config.validate(config_hash)`
- Runtime validation CLI: `html2rss validate config.yml`
- Packaged JSON file: `schema/html2rss-config.schema.json`

If you are an editor integration, automation script, or AI tool, prefer these stable discovery points:

- call `html2rss schema` to read the current exported schema
- read `schema/html2rss-config.schema.json` when working from the repository or installed gem
- use `Html2rss::Config.schema_path` if you already have Ruby loaded
- use `Html2rss::Config.validate` or `html2rss validate config.yml` when you need authoritative runtime validation of selector references

Run `bundle exec rake config:schema` before committing to regenerate `schema/html2rss-config.schema.json` and keep the checked-in JSON Schema in sync with the validators. The exported schema covers client-side validation, while runtime validation remains authoritative for dynamic cross-field checks such as selector-key references.

## 🧪 Testing

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💖 Sponsoring

If you find `html2rss` useful, please consider [sponsoring the project](https://github.com/sponsors/gildesmarais).
