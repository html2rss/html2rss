![html2rss logo](https://github.com/gildesmarais/html2rss/raw/master/support/logo.png)

[![Build Status](https://travis-ci.org/gildesmarais/html2rss.svg?branch=master)](https://travis-ci.org/gildesmarais/html2rss)
[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/)
[![Coverage Status](https://coveralls.io/repos/github/gildesmarais/html2rss/badge.svg?branch=master)](https://coveralls.io/github/gildesmarais/html2rss?branch=master)
[![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://www.rubydoc.info/gems/html2rss)
![Retro Badge: valid RSS](https://validator.w3.org/feed/images/valid-rss-rogers.png)

This Ruby gem builds RSS 2.0 feeds from a _feed config_.

With the _feed config_ containing the URL to scrape and
CSS selectors for information extraction (like title, URL, ...) your RSS builds.
[Extractors](#using-extractors) and chain-able [post processors](#using-post-processors) make information extraction, processing and sanitizing a breeze.
[Scraping JSON](#scraping-json) responses and [setting HTTP request headers](#set-any-http-header-in-the-request) is supported, too.

**Searching for a ready to use "website to RSS" solution?**
[Check out `html2rss-web`!](https://github.com/gildesmarais/html2rss-web)

## Installation

|                                    🤩 Like it? | Star it! ⭐️         |
| ---------------------------------------------: | -------------------- |
| Add this line to your application's `Gemfile`: | `gem 'html2rss'`     |
|                                  Then execute: | `bundle`             |
|                                  In your code: | `require 'html2rss'` |

## Building a feed config

Here's a minimal working example:

```ruby
require 'html2rss'

rss =
  Html2rss.feed(
    channel: {
      title: 'StackOverflow: Hot Network Questions',
      url: 'https://stackoverflow.com/questions'
    },
    selectors: {
      items: { selector: '#hot-network-questions > ul > li' },
      title: { selector: 'a' },
      link: { selector: 'a', extractor: 'href' }
    }
  )

puts rss
```

A _feed config_ consists of a `channel` and a `selectors` Hash.
The contents of both hashes are explained below.

**Looks too complicated?** See [`html2rss-configs`](https://github.com/gildesmarais/html2rss-configs) for ready-made feed configs!

### The `channel`

| attribute     |          | type    | remark                  |
| ------------- | -------- | ------- | ----------------------- |
| `title`       | required | String  |                         |
| `url`         | required | String  |                         |
| `ttl`         | optional | Integer | time to live in minutes |
| `description` | options  | String  |                         |
| `headers`     | optional | Hash    | See notes below.        |

### The `selectors`

You must provide an `items` selector hash which contains the CSS selector.
`items` needs to return a collection of HTML tags.
The other selectors are scoped to the tags of the items' collection.

To build a
[valid RSS 2.0 item](http://www.rssboard.org/rss-profile#element-channel-item)
each item has to have at least a `title` or a `description`.

Your `selectors` can contain arbitrary selector names, but only these
will make it into the RSS feed:

| RSS 2.0 tag   | name in html2rss | remark                      |
| ------------- | ---------------- | --------------------------- |
| `title`       | `title`          |                             |
| `description` | `description`    | Supports HTML.              |
| `link`        | `link`           | A URL.                      |
| `author`      | `author`         |                             |
| `category`    | `categories`     | See notes below.            |
| `enclosure`   | `enclosure`      | See notes below.            |
| `pubDate`     | `update`         | An instance of `Time`.      |
| `guid`        | `guid`           | Generated from the `title`. |
| `comments`    | `comments`       | A URL.                      |
| `source`      | ~~source~~       | Not yet supported.          |

### The `selector` hash

Your selector hash can have these attributes:

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
- [See file list of extractors](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/item_extractors).

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

Extractors can require additional attributes on the selector hash.  
👉 [Read their docs for usage examples](https://www.rubydoc.info/gems/html2rss/Html2rss/ItemExtractors).

## Using post processors

Extracted information can be further manipulated with post processors.

⚠️ Always make use of the `sanitize_html` post processor for HTML content. _Never trust the internet!_ ⚠️

- [See file list of post processors](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/attribute_post_processors).

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

👉 [Read their docs for usage examples.](https://www.rubydoc.info/gems/html2rss/Html2rss/AttributePostProcessors)

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
          # %s

          Price: %s
        methods:
          - self
          - price
      - name: markdown_to_html
```

Note the use of `|` for a multi-line String in YAML.

</details>

## Adding `<category>` tags to an item

The `categories` selector takes an array of selector names. The value of those
selectors will become a <category> on the RSS item.

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

## Adding an `<enclosure>` to an item

An enclosure can be 'anything', e.g. a image, audio or video file..

The `enclosure` selector needs to return a URL of the content to enclose. If the extracted URL is relative, it will be converted to an absolute one using the channel's URL as base.

Since html2rss does no further inspection of the enclosure, its support comes with trade-offs:

1. The content-type is guessed from the file extension of the URL.
2. If the content-type guessing fails, it will default to `application/octet-stream`.
3. The content-length will always be undetermined and thus stated as `0` bytes.

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

## Scraping JSON

Although this gem is called **html**​*2rss*, it's possible to scrape and process JSON.

Adding `json: true` to the channel config will convert the JSON response to XML.

<details>
  <summary>See a Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {
    url: 'https://example.com', title: 'Example with JSON', json: true
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
  title: "Example with JSON"
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
      title: "Example with http headers",
      headers: {
        "User-Agent" => "html2rss-request",
        "X-Something" => "Foobar",
        "Authorization" => "Token deadbea7",
        "Cookie" => "monster=MeWantCookie"
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
  title: "Example with http headers"
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

## Usage with a YAML config file

This step is not required to work with this gem. If you're using
[`html2rss-web`](https://github.com/gildesmarais/html2rss-web)
and want to create your private feed configs, keep on reading!

First, create your YAML file, e.g. called `config.yml`.
This file will contain your global config and feed configs.

Example:

```yml
headers:
  'User-Agent': "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1"
feeds:
  myfeed:
    channel:
    selectors:
  myotherfeed:
    channel:
    selectors:
```

Your feed configs go below `feeds`. Everything else is part of the global config.

Build your feeds like this:

```ruby
require 'html2rss'

myfeed = Html2rss.feed_from_yaml_config('config.yml', 'myfeed')
myotherfeed = Html2rss.feed_from_yaml_config('config.yml', 'myotherfeed')
```

Find a full example of a `config.yml` at [`spec/config.test.yml`](https://github.com/gildesmarais/html2rss/blob/master/spec/config.test.yml).

## Gotchas and tips & tricks

- Check that the channel URL does not redirect to a mobile page with a different markup structure.
- Do not rely on your web browser's developer console. html2rss does not execute JavaScript.
- Fiddling with [`curl`](https://github.com/curl/curl) and [`pup`](https://github.com/ericchiang/pup) to find the selectors seems efficient (`curl URL | pup`).

## Development

After checking out the repository, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

<details>
  <summary>Releasing a new version</summary>

1. `git pull`
2. increase version in `lib/html2rss/version.rb`
3. `bundle`
4. commit the changes
5. `git tag v....`
6. [`standard-changelog -f`](https://github.com/conventional-changelog/conventional-changelog/tree/master/packages/standard-changelog)
7. `git add CHANGELOG.md && git commit --amend`
8. `git tag v.... -f`
9. `git push && git push --tags`

</details>

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gildesmarais/html2rss.
