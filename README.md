![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png) [![](http://img.shields.io/liberapay/goal/gildesmarais.svg?logo=liberapa)](https://liberapay.com/gildesmarais/donate)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from a _feed config_.

With the _feed config_, you provide a URL to scrape and CSS selectors for extracting information (like title, URL, etc.). The gem builds the RSS feed accordingly. [Extractors](#using-extractors) and chainable [post processors](#using-post-processors) make information extraction, processing, and sanitizing a breeze. The gem also supports [scraping JSON](#scraping-and-handling-json-responses) responses and [setting HTTP request headers](#set-any-http-header-in-the-request).

**Looking for a ready-to-use app to serve generated feeds via HTTP?** [Check out `html2rss-web`](https://github.com/html2rss/html2rss-web)!

Support the development by sponsoring this project on GitHub. Thank you! 💓

## Installation

| Install | `gem install html2rss` |
| ------- | ---------------------- |
| Usage   | `html2rss help`        |

You can also install it as a dependency in your Ruby project:

|                      🤩 Like it? | Star it! ⭐️         |
| -------------------------------: | -------------------- |
| Add this line to your `Gemfile`: | `gem 'html2rss'`     |
|                    Then execute: | `bundle`             |
|                    In your code: | `require 'html2rss'` |

## Generating a feed on the CLI

Create a file called `my_config_file.yml` with this example content:

```yml
channel:
  url: https://stackoverflow.com/questions
selectors:
  items:
    selector: "#hot-network-questions > ul > li"
  title:
    selector: a
  link:
    selector: a
    extractor: href
```

Build the RSS with: `html2rss feed ./my_config_file.yml`.

## Generating a feed with Ruby

Here's a minimal working example in Ruby:

```ruby
require 'html2rss'

rss =
  Html2rss.feed(
    channel: { url: 'https://stackoverflow.com/questions' },
    selectors: {
      items: { selector: '#hot-network-questions > ul > li' },
      title: { selector: 'a' },
      link: { selector: 'a', extractor: 'href' }
    }
  )

puts rss
```

## The _feed config_ and its options

A _feed config_ consists of a `channel` and a `selectors` hash. The contents of both hashes are explained below.

Good to know:

- You'll find extensive example feed configs at [`spec/*.test.yml`](https://github.com/html2rss/html2rss/tree/master/spec).
- See [`html2rss-configs`](https://github.com/html2rss/html2rss-configs) for ready-made feed configs!
- If you've created feed configs, you're invited to send a PR to [`html2rss-configs`](https://github.com/html2rss/html2rss-configs) to make your config available to the public.

Alright, let's move on.

### The `channel`

| attribute     |              | type    | default        | remark                                     |
| ------------- | ------------ | ------- | -------------- | ------------------------------------------ |
| `url`         | **required** | String  |                |                                            |
| `title`       | optional     | String  | auto-generated |                                            |
| `description` | optional     | String  | auto-generated |                                            |
| `ttl`         | optional     | Integer | `360`          | TTL in _minutes_                           |
| `time_zone`   | optional     | String  | `'UTC'`        | TimeZone name                              |
| `language`    | optional     | String  | `'en'`         | Language code                              |
| `author`      | optional     | String  |                | Format: `email (Name)`                     |
| `headers`     | optional     | Hash    | `{}`           | Set HTTP request headers. See notes below. |
| `json`        | optional     | Boolean | `false`        | Handle JSON response. See notes below.     |

#### Dynamic parameters in `channel` attributes

Sometimes there are structurally similar pages with different URLs. In such cases, you can add _dynamic parameters_ to the channel's attributes.

Example of a dynamic `id` parameter in the channel URLs:

```yml
channel:
  url: "http://domainname.tld/whatever/%<id>s.html"
```

Command line usage example:

```sh
bundle exec html2rss feed the_feed_config.yml id=42
```

<details><summary>See a Ruby example</summary>

```ruby
config = Html2rss::Config.new({ channel: { url: 'http://domainname.tld/whatever/%<id>s.html' } }, {}, { id: 42 })
Html2rss.feed(config)
```

</details>

See the more complex formatting options of the [`sprintf` method](https://ruby-doc.org/core/Kernel.html#method-i-sprintf).

### The `selectors`

First, you must give an **`items`** selector hash, which contains a CSS selector. The selector selects a collection of HTML tags from which the RSS feed items are built. Except for the `items` selector, all other keys are scoped to each item of the collection.

To build a [valid RSS 2.0 item](http://www.rssboard.org/rss-profile#element-channel-item), you need at least a `title` **or** a `description`. You can have both.

Having an `items` and a `title` selector is enough to build a simple feed.

Your `selectors` hash can contain arbitrary named selectors, but only a few will make it into the RSS feed (due to the RSS 2.0 specification):

| RSS 2.0 tag   | name in `html2rss` | remark                                      |
| ------------- | ------------------ | ------------------------------------------- |
| `title`       | `title`            |                                             |
| `description` | `description`      | Supports HTML.                              |
| `link`        | `link`             | A URL.                                      |
| `author`      | `author`           |                                             |
| `category`    | `categories`       | See notes below.                            |
| `guid`        | `guid`             | Default title/description. See notes below. |
| `enclosure`   | `enclosure`        | See notes below.                            |
| `pubDate`     | `updated`          | An instance of `Time`.                      |
| `comments`    | `comments`         | A URL.                                      |
| `source`      | ~~source~~         | Not yet supported.                          |

### The `selector` hash

Every named selector in your `selectors` hash can have these attributes:

| name           | value                                                    |
| -------------- | -------------------------------------------------------- |
| `selector`     | The CSS selector to select the tag with the information. |
| `extractor`    | Name of the extractor. See notes below.                  |
| `post_process` | A hash or array of hashes. See notes below.              |

## Using extractors

Extractors help with extracting the information from the selected HTML tag.

- The default extractor is `text`, which returns the tag's inner text.
- The `html` extractor returns the tag's outer HTML.
- The `href` extractor returns a URL from the tag's `href` attribute and corrects relative ones to absolute ones.
- The `attribute` extractor returns the value of that tag's attribute.
- The `static` extractor returns the configured static value (it doesn't extract anything).
- [See file list of extractors](https://github.com/html2rss/html2rss/tree/master/lib/html2rss/item_extractors).

Extractors might need extra attributes on the selector hash. 👉 [Read their docs for usage examples](https://www.rubydoc.info/gems/html2rss/Html2rss/ItemExtractors).

<details><summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {}, selectors: { link: { selector: 'a', extractor: 'href' } }
)
```

</details>

<details><summary>See a YAML feed config example</summary>

```yml
channel:
  # ... omitted
selectors:
  # ... omitted
  link:
    selector: "a"
    extractor: "href"
```

</details>

## Using post processors

Extracted information can be further manipulated with post processors.

| name               |                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------- |
| `gsub`             | Allows global substitution operations on Strings (Regexp or simple pattern).          |
| `html_to_markdown` | HTML to Markdown, using [reverse_markdown](https://github.com/xijo/reverse_markdown). |
| `markdown_to_html` | converts Markdown to HTML, using [kramdown](https://github.com/gettalong/kramdown).   |
| `parse_time`       | Parses a String containing a time in a time zone.                                     |
| `parse_uri`        | Parses a String as URL.                                                               |
| `sanitize_html`    | Strips unsafe and uneeded HTML and adds security related attributes.                  |
| `substring`        | Cuts a part off of a String, starting at a position.                                  |
| `template`         | Based on a template, it creates a new String filled with other selectors values.      |

⚠️ Always make use of the `sanitize_html` post processor for HTML content. _Never trust the internet!_ ⚠️

### Post processor `gsub`

The post processor `gsub` makes use of Ruby's [`gsub`](https://apidock.com/ruby/String/gsub) method.

| key           | type   | required | note                        |
| ------------- | ------ | -------- | --------------------------- |
| `pattern`     | String | yes      | Can be Regexp or String.    |
| `replacement` | String | yes      | Can be a [backreference](). |

<details><summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    title: { selector: 'a', post_process: [{ name: 'gsub', pattern: 'foo', replacement: 'bar' }] }
  }
)
```

</details>

<details><summary>See a YAML feed config example</summary>

```yml
channel:
  # ... omitted
selectors:
  # ... omitted
  title:
    selector: "a"
    post_process:
      - name: "gsub"
        pattern: "foo"
        replacement: "bar"
```

</details>

## Scraping and handling JSON responses

By default, `html2rss` assumes the URL responds with HTML. However, it can also handle JSON responses. The JSON must return an Array or Hash.

| key        | required | default | note                                                 |
| ---------- | -------- | ------- | ---------------------------------------------------- |
| `json`     | optional | false   | If set to `true`, the response is parsed as JSON.    |
| `jsonpath` | optional | $       | Use [JSONPath syntax]() to select nodes of interest. |

<details> <summary>See a Ruby example</summary>

```
ruby
Copy code
Html2rss.feed(
  channel: { url: 'http://domainname.tld/whatever.json', json: true },
  selectors: { title: { selector: 'foo' } }
)
```

</details>

<details><summary>See a YAML feed config example</summary>

```yml
channel:
  url: "http://domainname.tld/whatever.json"
  json: true
selectors:
  title:
    selector: "foo"
```

</details>

## Set any HTTP header in the request

To set HTTP request headers, you can add them to the channel's `headers` hash. This is useful for APIs that require an Authorization header.

```yml
channel:
  url: "https://example.com/api/resource"
  headers:
    Authorization: "Bearer YOUR_TOKEN"
selectors:
  # ... omitted
```

Or for setting a User-Agent:

```yml
channel:
  url: "https://example.com"
  headers:
    User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
selectors:
  # ... omitted
```

### Contributing

1. Fork it ( <https://github.com/html2rss/html2rss/fork> )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
