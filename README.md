![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![CI](https://github.com/html2rss/html2rss/workflows/lint%20and%20test/badge.svg)](https://github.com/html2rss/html2rss/actions)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites by scraping HTML or JSON content with **CSS selectors** or **auto-detection**.

This gem is the core of the [html2rss-web](https://github.com/html2rss/html2rss-web) application.

## 🌐 Community & Resources

| Resource                              | Description                                                 | Link                                                               |
| ------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------ |
| **📚 Documentation & Feed Directory** | Complete guides, tutorials, and browse 100+ pre-built feeds | [html2rss.github.io](https://html2rss.github.io)                   |
| **💬 Community Discussions**          | Get help, share ideas, and connect with other users         | [GitHub Discussions](https://github.com/orgs/html2rss/discussions) |
| **📋 Project Board**                  | Track development progress and upcoming features            | [View Project Board](https://github.com/orgs/html2rss/projects)    |
| **💖 Support Development**            | Help fund ongoing development and maintenance               | [Sponsor on GitHub](https://github.com/sponsors/gildesmarais)      |

**Quick Start Options:**

- **New to RSS?** → Start with the [web application](https://html2rss.github.io/web-application)
- **Ruby Developer?** → Check out the [Ruby gem documentation](https://html2rss.github.io/ruby-gem)
- **Need a specific feed?** → Browse the [feed directory](https://html2rss.github.io/feed-directory)
- **Want to contribute?** → See our [contributing guide](https://html2rss.github.io/get-involved/contributing)

## ✨ Features

- 🎯 **CSS Selector Support** - Extract content using familiar CSS selectors
- 🤖 **Auto-Detection** - Automatically detect content using Schema.org, JSON state, and semantic HTML
- 🔄 **Multiple Request Strategies** - Faraday for static sites, Browserless for JS-heavy sites
- 🛠️ **Post-Processing** - Template rendering, HTML sanitization, time parsing, and more
- 🧪 **Comprehensive Testing** - 95%+ test coverage with RSpec
- 📚 **Full Documentation** - YARD documentation and comprehensive guides

## 🚀 Quick Start

For installation and usage instructions, please visit the [project website](https://html2rss.github.io/ruby-gem).

### 💻 Try in Browser

You can develop html2rss directly in your browser using GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=html2rss/html2rss)

The Codespace comes pre-configured with Ruby 3.4 (compatible with Ruby 4.0), all dependencies, and VS Code extensions ready to go!

## 📚 Documentation

The full documentation for the `html2rss` gem is available on the [project website](https://html2rss.github.io/ruby-gem).

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

## 📄 Configuration Notes

### Paginated feeds

`html2rss` can follow a single `rel="next"` pagination chain when you configure `selectors.items.pagination.max_pages`.

```yaml
channel:
  url: https://example.com/news

selectors:
  items:
    selector: article
    pagination:
      max_pages: 3
  title:
    selector: h1
  url:
    selector: a
    extractor: href
```

Behavior:

- `max_pages` is the total page budget for the item selector chain, including the initial page.
- Pagination follows strict `link[rel~=next]` or `a[rel~=next]` targets only.
- Follow-up pages stay on the original origin by default and stop when the shared request budget is exhausted.
- The same request safeguards apply to pagination and Browserless navigation: timeout limits, redirect limits, response-size guards, and private-network denial.

## 🧪 Testing

- **RSpec** for comprehensive testing
- **95%+ code coverage** with SimpleCov
- **VCR** for HTTP interaction testing
- **RuboCop** for code style enforcement
- **Reek** for code smell detection

## 🔧 Development Tools

- **Ruby LSP** for IntelliSense and language features
- **Debug** for modern debugging and exploration
- **YARD** for documentation generation
- **GitHub Actions** for CI/CD

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

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💖 Sponsoring

If you find `html2rss` useful, please consider [sponsoring the project](https://github.com/sponsors/gildesmarais).
