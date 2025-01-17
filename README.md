![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss) ![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png)

`html2rss` is a Ruby gem that generates RSS 2.0 feeds from websites automatically, and as a fallback via _feed config_.

With the _feed config_, you provide a URL to scrape and CSS selectors for extracting information (like title, URL, etc.). The gem builds the RSS feed accordingly. [Extractors](#using-extractors) and chainable [post processors](#using-post-processors) make information extraction, processing, and sanitizing a breeze. The gem also supports [scraping JSON](#scraping-and-handling-json-responses) responses and [setting HTTP request headers](#set-any-http-header-in-the-request).

**Looking for a ready-to-use app to serve generated feeds via HTTP?** [Check out `html2rss-web`](https://github.com/html2rss/html2rss-web)!

Support the development by sponsoring this project on GitHub. Thank you! 💓

## Generating a feed on the CLI

[Install Ruby](https://www.ruby-lang.org/en/documentation/installation/) (latest version is recommended) on your machine and run `gem install html2rss` in your terminal.

After the installation has finished, `html2rss help` will print usage information.

### using automatic generation

html2rss offers an automatic RSS generation feature. Try it on CLI with:

`html2rss auto https://unmatchedstyle.com/`

### creating a feed config file and using it

If the results are not to your satisfaction, you can create a feed config file.

Create a file called `my_config_file.yml` with this sample content:

```yml
channel:
  url: https://unmatchedstyle.com
selectors:
  items:
    selector: "article[id^='post-']"
  title:
    selector: h2
  link:
    selector: a
    extractor: href
  description:
    selector: ".post-content"
    post_process:
      - name: sanitize_html
auto_source: # this enables auto_source additionally. Remove if you don't want that.
```

Build the feed from this config with: `html2rss feed ./my_config_file.yml`.

## Generating a feed with Ruby

You can also install it as a dependency in your Ruby project:

|                      🤩 Like it? | Star it! ⭐️         |
| -------------------------------: | -------------------- |
| Add this line to your `Gemfile`: | `gem 'html2rss'`     |
|                    Then execute: | `bundle`             |
|                    In your code: | `require 'html2rss'` |

Here's a minimal working example using Ruby:

```ruby
require 'html2rss'

rss = Html2rss.feed(
  channel: { url: 'https://stackoverflow.com/questions' },
  auto_source: {}
)

puts rss

```

and instead with `auto_source`, provide `selectors`:

```ruby
require 'html2rss'

rss = Html2rss.feed(
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
| `author`      | optional     | String  |                | Format: `email (Name)`                     |
| `ttl`         | optional     | Integer | auto-generated | TTL in _minutes_, falls back to `360`      |
| `language`    | optional     | String  | auto-generated | Language code                              |
| `time_zone`   | optional     | String  | `'UTC'`        | TimeZone name                              |
| `headers`     | optional     | Hash    | `{}`           | Set HTTP request headers. See notes below. |

#### Dynamic parameters in `channel` attributes

Sometimes there are structurally similar pages with different URLs. In such cases, you can add _dynamic parameters_ to the channel's attributes.

Example of an dynamic parameter `id` in the channel URL:

```yml
channel:
  url: "http://domainname.tld/whatever/%<id>s.html"
```

Command line usage example:

```sh
html2rss feed the_feed_config.yml --params id:42 foo:bar
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
| `pubDate`     | `published_at`     | An instance of `Time`.                      |
| `comments`    | `comments`         | A URL.                                      |
| `source`      | ~~source~~         | Not yet supported.                          |

### Build RSS 2.0 item attributes by specifying selectors

Every named selector (i.e. `title`, `description`, see table above) in your `selectors` hash can have these attributes:

| name           | value                                                    |
| -------------- | -------------------------------------------------------- |
| `selector`     | The CSS selector to select the tag with the information. |
| `extractor`    | Name of the extractor. See notes below.                  |
| `post_process` | A hash or array of hashes. See notes below.              |

#### Using extractors

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

### Using post processors

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

#### Chaining post processors

Pass an array to `post_process` to chain the post processors.

<details><summary>YAML example: build the description from a template String (in Markdown) and convert that Markdown to HTML</summary>

```yml
channel:
  # ... omitted
selectors:
  # ... omitted
  price:
    selector: '.price'
  description:
    selector: '.section'
    post_process:
      - name: template
        string: |
          # %{self}

          Price: %{price}
      - name: markdown_to_html
```

</details>

##### Post processor `gsub`

The post processor `gsub` makes use of Ruby's [`gsub`](https://apidock.com/ruby/String/gsub) method.

| key           | type   | required | note                     |
| ------------- | ------ | -------- | ------------------------ |
| `pattern`     | String | yes      | Can be Regexp or String. |
| `replacement` | String | yes      | Can be a backreference.  |

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

#### Adding `<category>` tags to an item

The `categories` selector takes an array of selector names. Each value of those
selectors will become a `<category>` on the RSS item.

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    genre: {
      # ... omitted
      selector: '.genre'
    },
    branch: { selector: '.branch' },
    categories: %i[genre branch]
  }
)
```

</details>

<details>
  <summary>See a YAML feed config example</summary>

```yml
channel:
  # ... omitted
selectors:
  # ... omitted
  genre:
    selector: ".genre"
  branch:
    selector: ".branch"
  categories:
    - genre
    - branch
```

</details>

#### Custom item GUID

By default, html2rss generates a GUID from the `title` or `description`.

If this does not work well, you can choose other attributes from which the GUID is build.
The principle is the same as for the categories: pass an array of selectors names.

In all cases, the GUID is a base-36 encoded CRC32 checksum.

<details><summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    title: {
      # ... omitted
      selector: 'h1'
    },
    link: { selector: 'a', extractor: 'href' },
    guid: %i[link]
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
    selector: "h1"
  link:
    selector: "a"
    extractor: "href"
  guid:
    - link
```

</details>

#### Adding an `<enclosure>` tag to an item

An enclosure can be any file, e.g. a image, audio or video - think Podcast.

The `enclosure` selector needs to return a URL of the content to enclose. If the extracted URL is relative, it will be converted to an absolute one using the channel's URL as base.

Since `html2rss` does no further inspection of the enclosure, its support comes with trade-offs:

1. The content-type is guessed from the file extension of the URL, unless one is specified in `content_type`.
2. If the content-type guessing fails, it will default to `application/octet-stream`.
3. The content-length will always be undetermined and therefore stated as `0` bytes.

Read the [RSS 2.0 spec](http://www.rssboard.org/rss-profile#element-channel-item-enclosure) for further information on enclosing content.

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    enclosure: {
      selector: 'audio',
      extractor: 'attribute',
      attribute: 'src',
      content_type: 'audio/mp3'
    }
  }
)
```

</details>

<details>
  <summary>See a YAML feed config example</summary>

```yml
channel:
  # ... omitted
selectors:
  # ... omitted
  enclosure:
    selector: "audio"
    extractor: "attribute"
    attribute: "src"
    content_type: "audio/mp3"
```

</details>

## Scraping and handling JSON responses

When the requested website returns a application/json content-typed response, i.e. you specified an Accept header in the request, html2rss converts it to XML.

That is XML you can query using CSS selectors. The JSON response must be an Array or Hash for this to work.

<details><summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {
    url: 'http://domainname.tld/whatever.json',
    headers: {
      Accept: 'application/json'
    }
  },
  selectors: { title: { selector: 'foo' } }
)
```

</details>

<details><summary>See a YAML feed config example</summary>

```yml
channel:
  url: "http://domainname.tld/whatever.json"
  headers:
    Accept: application/json
selectors:
  title:
    selector: "foo"
```

</details>

<details>
  <summary>See example of a converted JSON object</summary>

This JSON object:

```json
{
  "data": [{ "title": "Headline", "url": "https://example.com" }]
}
```

converts to:

```xml
<object>
  <data>
    <array>
      <object>
        <title>Headline</title>
        <url>https://example.com</url>
      </object>
    </array>
  </data>
</object>
```

Your items selector would be `array > object`, the item's `link` selector would be `url`.

</details>

<details>
  <summary>See example of a converted JSON array</summary>

This JSON array:

```json
[{ "title": "Headline", "url": "https://example.com" }]
```

converts to:

```xml
<array>
  <object>
    <title>Headline</title>
    <url>https://example.com</url>
  </object>
</array>
```

Your items selector would be `array > object`, the item's `link` selector would be `url`.

</details>

## Customization of how requests to the channel URL are sent

By default, html2rss issues a naiive HTTP request and extracts information from the response. That is performant and works for many websites.

However, modern websites often do not render much HTML on the server, but evaluate JavaScript on the client to create the HTML. In such cases, the default strategy will not find the "juicy content".

### Use Browserless.io

You can use _Browserless.io_ to run a Chrome browser and return the website's source code after the website generated it.
For this, you can either run your own Browserless.io instance (Docker image available -- [read their license](https://github.com/browserless/browserless/pkgs/container/chromium#licensing)!) or pay them for a hosted instance.

To run a local Browserless.io instance, you can use the following Docker command:

```sh
docker run \
  --rm \
  -p 3000:3000 \
  -e "CONCURRENT=10" \
  -e "TOKEN=6R0W53R135510" \
  ghcr.io/browserless/chromium
```

To make html2rss use your instance,

1. specify the environment variables accordingly, and
2. use the `browserless` strategy for those websites.

When running locally with commands from above, you can skip setting the environment variables, as they are aligned with the default values.

```sh
BROWSERLESS_IO_WEBSOCKET_URL="ws://127.0.0.1:3000" BROWSERLESS_IO_API_TOKEN="6R0W53R135510" \
  html2rss auto --strategy=browserless https://example.com
```

When using traditional feed configs, inside your channel config set `strategy: browserless`.

<details><summary>See a YAML feed config example</summary>

```yml
channel:
  url: https://www.imdb.com/user/ur67728460/ratings
  time_zone: UTC
  ttl: 1440
  strategy: browserless
  headers:
    User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
selectors:
  items:
    selector: "li.ipc-metadata-list-summary-item"
  title:
    selector: ".ipc-title__text"
    post_process:
      - name: gsub
        pattern: "/^(\\d+.)\\s/"
        replacement: ""
      - name: template
        string: "%{self} rated with: %{user_rating}"
  link:
    selector: "a.ipc-title-link-wrapper"
    extractor: "href"
  user_rating:
    selector: "[data-testid='ratingGroup--other-user-rating'] > .ipc-rating-star--rating"
```

</details>

### Set any HTTP header in the request

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

## Usage with a YAML config file

This step is not required to work with this gem. If you're using
[`html2rss-web`](https://github.com/html2rss/html2rss-web)
and want to create your private feed configs, keep on reading!

First, create a YAML file, e.g. `feeds.yml`. This file will contain your global config and multiple feed configs under the key `feeds`.

Example:

```yml
headers:
  "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1"
feeds:
  myfeed:
    channel:
    selectors:
  myotherfeed:
    channel:
    selectors:
```

Your feed configs go below `feeds`. Everything else is part of the global config.

Find a full example of a `feeds.yml` at [`spec/fixtures/feeds.test.yml`](https://github.com/html2rss/html2rss/blob/master/spec/fixtures/feeds.test.yml).

Now you can build your feeds like this:

<details>
  <summary>Build feeds in Ruby</summary>

```ruby
require 'html2rss'

myfeed = Html2rss.feed_from_yaml_config('feeds.yml', 'myfeed')
myotherfeed = Html2rss.feed_from_yaml_config('feeds.yml', 'myotherfeed')
```

</details>

<details>
  <summary>Build feeds on the command line</summary>

```sh
html2rss feed feeds.yml myfeed
html2rss feed feeds.yml myotherfeed
```

</details>

## Display the RSS feed nicely in a web browser

To display RSS feeds nicely in a web browser, you can:

- add a plain old CSS stylesheet, or
- use XSLT (e**X**tensible **S**tylesheet **L**anguage **T**ransformations).

A web browser will apply these stylesheets and show the contents as described.

In a CSS stylesheet, you'd use `element` selectors to apply styles.

If you want to do more, then you need to create a XSLT. XSLT allows you
to use a HTML template and to freely design the information of the RSS,
including using JavaScript and external resources.

You can add as many stylesheets and types as you like. Just add them to your global configuration.

<details>
  <summary>Ruby: a stylesheet config example</summary>

```ruby
config = Html2rss::Config.new(
  { channel: {}, selectors: {} }, # omitted
  {
    stylesheets: [
      {
        href: '/relative/base/path/to/style.xls',
        media: :all,
        type: 'text/xsl'
      },
      {
        href: 'http://example.com/rss.css',
        media: :all,
        type: 'text/css'
      }
    ]
  }
)

Html2rss.feed(config)
```

</details>

<details>
  <summary>YAML: a stylesheet config example</summary>

```yml
stylesheets:
  - href: "/relative/base/path/to/style.xls"
    media: "all"
    type: "text/xsl"
  - href: "http://example.com/rss.css"
    media: "all"
    type: "text/css"
feeds:
  # ... omitted
```

</details>

Recommended further readings:

- [How to format RSS with CSS on lifewire.com](https://www.lifewire.com/how-to-format-rss-3469302)
- [XSLT: Extensible Stylesheet Language Transformations on MDN](https://developer.mozilla.org/en-US/docs/Web/XSLT)
- [The XSLT used by html2rss-web](https://github.com/html2rss/html2rss-web/blob/master/public/rss.xsl)

## Gotchas and tips & tricks

- Check that the channel URL does not redirect to a mobile page with a different markup structure.
- Do not rely on your web browser's developer console. `html2rss` does not execute JavaScript.
- Fiddling with [`curl`](https://github.com/curl/curl) and [`pup`](https://github.com/ericchiang/pup) to find the selectors seems efficient (`curl URL | pup`).
- [CSS selectors are versatile. Here's an overview.](https://www.w3.org/TR/selectors-4/#overview)

## Contributing

Find ideas what to contribute in:

1. <https://github.com/orgs/html2rss/discussions>
2. the issues tracker: <https://github.com/html2rss/html2rss/issues>

To submit changes:

1. Fork this repo ( <https://github.com/html2rss/html2rss/fork> )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Implement a commit your changes (`git commit -am 'feat: add XYZ'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request using the Github web UI

## Development Helpers

1. `bin/setup`: installs dependencies and sets up the development environment.
2. for a modern Ruby development experience: install [`ruby-lsp`](https://github.com/Shopify/ruby-lsp) and integrate it to your IDE.

For example: [Ruby in Visual Studio Code](https://code.visualstudio.com/docs/languages/ruby).
