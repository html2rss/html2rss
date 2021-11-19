![html2rss logo](https://github.com/html2rss/html2rss/raw/master/support/logo.png)

[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/)
[![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss)
![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png)
[![](http://img.shields.io/liberapay/goal/gildesmarais.svg?logo=liberapa)](https://liberapay.com/gildesmarais/donate)

This Ruby gem builds RSS 2.0 feeds from a _feed config_.

With the _feed config_ containing the URL to scrape and
CSS selectors for information extraction (like title, URL, ...) your RSS builds.
[Extractors](#using-extractors) and chain-able [post processors](#using-post-processors)
make information extraction, processing and sanitizing a breeze.
[Scraping JSON](#scraping-and-handling-json-responses) responses and
[setting HTTP request headers](#set-any-http-header-in-the-request) is
supported, too.

**Searching for a ready to use app which serves generated feeds via HTTP?**
[Head over to `html2rss-web`!](https://github.com/html2rss/html2rss-web)

To support the development, feel free [to donate](https://liberapay.com/gildesmarais/donate). Thank you! 💓

## Installation

| Install | `gem install html2rss` |
| ------: | ---------------------- |
|   Usage | `html2rss help`        |

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

Here's a minimal working example within Ruby:

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

A _feed config_ consists of a `channel` and a `selectors` Hash.
The contents of both hashes are explained in the chapters below.

Good to know:

- You'll find extensive example feed configs at [`spec/*.test.yml`](https://github.com/html2rss/html2rss/tree/master/spec).
- See [`html2rss-configs`](https://github.com/html2rss/html2rss-configs) for ready-made feed configs!
- If you've already created feed configs, you're invited to send a PR to [`html2rss-configs`](https://github.com/html2rss/html2rss-configs) to make your config available to the general public.

Alright, let's move on.

### The `channel`

| attribute     |              | type    |        default | remark                                     |
| ------------- | ------------ | ------- | -------------: | ------------------------------------------ |
| `url`         | **required** | String  |                |                                            |
| `title`       | optional     | String  | auto-generated |                                            |
| `description` | optional     | String  | auto-generated |                                            |
| `ttl`         | optional     | Integer |          `360` | TTL in _minutes_                           |
| `time_zone`   | optional     | String  |        `'UTC'` | TimeZone name                              |
| `language`    | optional     | String  |         `'en'` | Language code                              |
| `author`      | optional     | String  |                | Format: `email (Name)`                     |
| `headers`     | optional     | Hash    |           `{}` | Set HTTP request headers. See notes below. |
| `json`        | optional     | Boolean |        `false` | Handle JSON response. See notes below.     |

#### Dynamic parameters in `channel` attributes

Sometimes there are structurally equal pages with different URLs. In such a case you can add _dynamic parameters_ to the channel's attributes.

Example of a dynamic `id` parameter in the channel URLs:

```yml
channel:
  url: "http://domainname.tld/whatever/%<id>s.html"
```

Command line usage example:

```
bundle exec html2rss feed the_feed_config.yml id=42
```

<details>
  <summary>See a Ruby example</summary>

```ruby
config = Html2rss::Config.new({ channel: { url: 'http://domainname.tld/whatever/%<id>s.html' } }, {}, { id: 42 })
Html2rss.feed(config)
```

</details>

See the _more complex formatting_ of the [`sprintf` method](https://ruby-doc.org/core/Kernel.html#method-i-sprintf) for formatting options.

### The `selectors`

First, you must give an **`items`** selector hash which contains a CSS selector. The selector selects a collection of HTML tags from which the RSS feed items are build.
Except the `items` selector, all other keys are scoped to each item of the collection.

Then, to build a
[valid RSS 2.0 item](http://www.rssboard.org/rss-profile#element-channel-item),
you need to have at least a `title` **or** a `description`. You can have both.

Having an `items` and a `title` selector is already enough to build a simple feed.

Your `selectors` Hash can contain arbitrary named selectors, but only a few will make it into the RSS feed (This due to the RSS 2.0 specification):

| RSS 2.0 tag   | name in `html2rss` | remark                                       |
| ------------- | ------------------ | -------------------------------------------- |
| `title`       | `title`            |                                              |
| `description` | `description`      | Supports HTML.                               |
| `link`        | `link`             | A URL.                                       |
| `author`      | `author`           |                                              |
| `category`    | `categories`       | See notes below.                             |
| `guid`        | `guid`             | Default title/description. See notes below.  |
| `enclosure`   | `enclosure`        | See notes below.                             |
| `pubDate`     | `updated`          | An instance of `Time`.                       |
| `comments`    | `comments`         | A URL.                                       |
| `source`      | ~~source~~         | Not yet supported.                           |

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

Extractors might need extra attributes on the selector hash.  
👉 [Read their docs for usage examples](https://www.rubydoc.info/gems/html2rss/Html2rss/ItemExtractors).

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {}, selectors: { link: { selector: 'a', extractor: 'href' } }
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
  link:
    selector: 'a'
    extractor: 'href'
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

- [See file list of post processors](https://github.com/html2rss/html2rss/tree/master/lib/html2rss/attribute_post_processors).

👉 [Read their docs for usage examples.](https://www.rubydoc.info/gems/html2rss/Html2rss/AttributePostProcessors)

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    description: {
      selector: '.content', post_process: { name: 'sanitize_html' }
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
  description:
    selector: '.content'
    post_process:
      - name: sanitize_html
```

</details>

### Chaining post processors

Pass an array to `post_process` to chain the post processors.

<details>
  <summary>YAML example: build the description from a template String (in Markdown) and convert that Markdown to HTML</summary>

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

Note the use of `|` for a multi-line String in YAML.

</details>

## Adding `<category>` tags to an item

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

## Custom item GUID

By default, html2rss generates a GUID from the `title` or `description`.

If this does not work well, you can choose other attributes from which the GUID is build.
The principle is the same as for the categories: pass an array of selectors names.

In all cases, the GUID is a SHA1-encoded string.

<details>
  <summary>See a Ruby example</summary>

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

<details>
  <summary>See a YAML feed config example</summary>

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

## Adding an `<enclosure>` tag to an item

An enclosure can be any file, e.g. a image, audio or video.

The `enclosure` selector needs to return a URL of the content to enclose. If the extracted URL is relative, it will be converted to an absolute one using the channel's URL as base.

Since `html2rss` does no further inspection of the enclosure, its support comes with trade-offs:

1. The content-type is guessed from the file extension of the URL.
2. If the content-type guessing fails, it will default to `application/octet-stream`.
3. The content-length will always be undetermined and therefore stated as `0` bytes.

Read the [RSS 2.0 spec](http://www.rssboard.org/rss-profile#element-channel-item-enclosure) for further information on enclosing content.

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    enclosure: { selector: 'img', extractor: 'attribute', attribute: 'src' }
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
    selector: "img"
    extractor: "attribute"
    attribute: "src"
```

</details>

## Scraping and handling JSON responses

Although this gem's name is **html**​*2rss*, it's possible to scrape and process JSON.

Adding `json: true` to the channel config will convert the JSON response to XML.

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {
    url: 'https://example.com', json: true
  },
  selectors: {} # ... omitted
)
```

</details>

<details>
  <summary>See a YAML feed config example</summary>

```yaml
channel:
  url: https://example.com
  json: true
selectors:
  # ... omitted
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
<hash>
  <data>
    <datum>
      <title>Headline</title>
      <url>https://example.com</url>
    </datum>
  </data>
</hash>
```

Your items selector would be `data > datum`, the item's `link` selector would be `url`.

Find further information in [ActiveSupport's `Hash.to_xml` documentation](https://apidock.com/rails/Hash/to_xml).

</details>

<details>
  <summary>See example of a converted JSON array</summary>

This JSON array:

```json
[{ "title": "Headline", "url": "https://example.com" }]
```

converts to:

```xml
<objects>
  <object>
    <title>Headline</title>
    <url>https://example.com</url>
  </object>
</objects>
```

Your items selector would be `objects > object`, the item's `link` selector would be `url`.

Find further information in [ActiveSupport's `Array.to_xml` documentation](https://apidock.com/rails/Array/to_xml).

</details>

## Set any HTTP header in the request

You can add any HTTP headers to the request to the channel URL.
Use this to e.g. have Cookie or Authorization information sent or to spoof the User-Agent.

<details>
  <summary>See a Ruby example</summary>
  
  ```ruby
  Html2rss.feed(
    channel: {
      url: 'https://example.com',
      headers: {
        "User-Agent": "html2rss-request",
        "X-Something": "Foobar",
        "Authorization": "Token deadbea7",
        "Cookie": "monster=MeWantCookie"
      }
    },
    selectors: {}
  )
  ```

</details>

<details>
  <summary>See a YAML feed config example</summary>

```yaml
channel:
  url: https://example.com
  headers:
    "User-Agent": "html2rss-request"
    "X-Something": "Foobar"
    "Authorization": "Token deadbea7"
    "Cookie": "monster=MeWantCookie"
selectors:
  # ...
```

</details>

The headers provided by the channel are merged into the global headers.

## Reverse the order of items

By default, `html2rss` keeps the order of the collection returned from the `items` selector. The `items` selector hash can optionally contain an `order` attribute.
If its value is `reverse`, the order of items in the RSS will reverse.

<details>
  <summary>See a YAML feed config example</summary>

```yml
channel:
  # ... omitted
selectors:
  items:
    selector: 'ul > li'
    order: 'reverse'
  # ... omitted
```

</details>

Note that the order of items, according to the RSS 2.0 spec, should not matter to the feed-consuming client.

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

Find a full example of a `feeds.yml` at [`spec/feeds.test.yml`](https://github.com/html2rss/html2rss/blob/master/spec/feeds.test.yml).

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
$ html2rss feed feeds.yml myfeed
$ html2rss feed feeds.yml myotherfeed
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
  config =  Html2rss::Config.new(
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

## Development

After checking out the repository, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

<details>
  <summary>Releasing a new version</summary>

1. `git pull`
2. increase version in `lib/html2rss/version.rb`
3. `bundle`
4. `git add Gemfile.lock lib/html2rss/version.rb`
5. `VERSION=$(ruby -e 'require "./lib/html2rss/version.rb"; puts Html2rss::VERSION')`
6. `git commit -m "chore: release $VERSION"`
7. `git tag v$VERSION`
8. [`standard-changelog -f`](https://github.com/conventional-changelog/conventional-changelog/tree/master/packages/standard-changelog)
9. `git add CHANGELOG.md && git commit --amend`
10. `git tag v$VERSION -f`
11. `git push && git push --tags`

</details>

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/html2rss/html2rss.
