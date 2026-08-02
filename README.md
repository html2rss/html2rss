![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![CI](https://github.com/html2rss/html2rss/workflows/lint%20and%20test/badge.svg)](https://github.com/html2rss/html2rss/actions)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites by scraping HTML or JSON content with **CSS selectors** or **auto-detection**.

This gem is the core of the [html2rss-web](https://github.com/html2rss/html2rss-web) application.

Most people looking for a first working feed should start with `html2rss-web`, run it with Docker, and open one of the included feeds from their own instance before moving to custom configs or the gem APIs.

## Documentation

Detailed usage guides, reference docs, and the feed directory live on the project website:

- [Ruby gem documentation](https://html2rss.github.io/ruby-gem)
- [Request strategies](https://html2rss.github.io/ruby-gem/reference/strategy) (`auto`, `faraday`, `botasaurus`, `browserless`)
- [Selectors & pagination](https://html2rss.github.io/ruby-gem/reference/selectors#paginated-feeds)
- [Web application](https://html2rss.github.io/web-application)
- [Feed directory](https://html2rss.github.io/feed-directory)
- [Contributing guide](https://html2rss.github.io/get-involved/contributing)
- [GitHub Discussions](https://github.com/orgs/html2rss/discussions)
- [Sponsor on GitHub](https://github.com/sponsors/gildesmarais)

Cloud development: [Open in GitHub Codespaces](https://github.com/codespaces/new?repo=html2rss/html2rss) (also covered in the [installation guide](https://html2rss.github.io/ruby-gem/installation)).

## Architecture

1. **Config** — loads and validates configuration (YAML/hash); schema via `html2rss schema` / `schema/html2rss-config.schema.json`
2. **RequestService** — fetches pages (`faraday`, `botasaurus`, or `browserless`)
3. **Selectors** — extracts content via CSS selectors with extractors/post-processors
4. **AutoSource** — auto-detects content (Schema.org, JSON state, semantic HTML, structural patterns)
5. **RssBuilder** — assembles Article objects and renders RSS 2.0

```text
Config -> Request -> Extraction -> Processing -> Building -> Output
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
