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

### AutoSource Pagination

`Html2rss::AutoSource` now understands common pagination hints such as `<link rel="next">`, `.pagination a`, and any custom CSS selectors you provide. Pagination is **enabled by default** but ships with a safe `max_pages: 1`, so the auto-source will only scrape the first page unless you opt-in to deeper crawling.

```yaml
auto_source:
  pagination:
    max_pages: 3          # follow up to 3 pages total (including the first)
    selectors:
      - '.pagination a.next'
      - '.load-more a'
```

- All additional page requests reuse the configured strategy (Faraday, Browserless, etc.) and headers from your feed config.
- Visited URLs are tracked to prevent loops when sites point pagination links back to previously-seen pages.
- Set `pagination.enabled: false` to skip pagination entirely.

## 🚀 Quick Start

For installation and usage instructions, please visit the [project website](https://html2rss.github.io/ruby-gem).

### 💻 Try in Browser

You can develop html2rss directly in your browser using GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=html2rss/html2rss)

The Codespace comes pre-configured with Ruby 3.4, all dependencies, and VS Code extensions ready to go!

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

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💖 Sponsoring

If you find `html2rss` useful, please consider [sponsoring the project](https://github.com/sponsors/gildesmarais).
