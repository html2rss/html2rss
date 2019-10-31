![html2rss logo](https://github.com/gildesmarais/html2rss/raw/master/support/logo.png)

[![Build Status](https://travis-ci.org/gildesmarais/html2rss.svg?branch=master)](https://travis-ci.org/gildesmarais/html2rss)
[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/)
[![Coverage Status](https://coveralls.io/repos/github/gildesmarais/html2rss/badge.svg?branch=master)](https://coveralls.io/github/gildesmarais/html2rss?branch=master)
[API docs on RubyDoc.info](https://www.rubydoc.info/gems/html2rss)

Request HTML from an URL and transform it to a Ruby RSS 2.0 object.

**Are you searching for a ready to use "website to RSS" solution?**
[Check out `html2rss-web`!](https://github.com/gildesmarais/html2rss-web)

The *feed config* contains the URL to scrape and
CSS selectors to extract the desired information (like title, URL, ...).  
This gem further provides [extractors](https://github.com/gildesmarais/html2rss/blob/master/lib/html2rss/item_extractors) (e.g. extract the information from an HTML attribute)
and chain-able [post processors](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/attribute_post_processors) to make information extraction, processing and sanitizing a breeze.

## Installation

Add this line to your application's Gemfile: `gem 'html2rss'`  
Then execute: `bundle`

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

puts rss.to_s
```

**Too complicated?** See [`html2rss-configs`](https://github.com/gildesmarais/html2rss-configs) for ready-made feed configs!

## Assigning categories to an item

The `categories` selector takes an array of selector names. The value of those
selectors will become a category on the item.

<details>
  <summary>See Ruby example</summary>

```ruby
Html2rss.feed(
  channel: {},
  selectors: {
    genre: {
      # ... omitted
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

## Using post processors

Sometimes the desired information is hard to extract or not in the format you'd
like it to be in.
For this case there are plenty of [post processors available](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/attribute_post_processors).

### Chaining post processors

Pass an array to `post_process` to chain the post processors.

<details>
  <summary>Build a description from a Template (Markdown) and convert it to HTML</summary>

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

## Adding an enclosure to an item

An enclosure can be 'anything', e.g. a image, audio or video file.

The config's `enclosure` selector needs to return a URL of the content to enclose. If the extracted URL is relative, it will be converted to an absolute one using the channel's url as a base.

Since html2rss does no further inspection of the enclosure, the support of this tag comes with trade-offs:

1. The content-type is guessed from the file extension of the URL.
2. If the content-type guessing fails, it will default to `application/octet-stream`.
3. The content-length will always be undetermined and thus stated as `0` bytes.

Read the [RSS 2.0 spec](http://www.rssboard.org/rss-profile#element-channel-item-enclosure) for further information on enclosing content.

<!-- TODO: add ruby example -->

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

Although this gem is called **html\***2rss\*, it's possible to scrape and process JSON.

Adding `json: true` to the channel config will convert the JSON response to XML.

<details>
  <summary>See a Ruby example</summary>

```ruby
feed = Html2rss.feed(
  channel: {
    url: "https://example.com",
    title: "Example with JSON",
    json: true
  },
  selectors: {
    # ... omitted
  }
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
  <summary>See how JSON objects are converted</summary>

This JSON object:

```json
{
  "data": [{ "title": "Headline", "url": "https://example.com" }]
}
```

will be converted to:

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

Find further information in [ActiveSupport's `Hash.to_xml` documentation](https://apidock.com/rails/Hash/to_xml) for the conversion.

</details>

<details>
  <summary>See how JSON arrays are converted</summary>

This JSON array:

```json
[{ "title": "Headline", "url": "https://example.com" }]
```

will be converted to:

```xml
<objects>
  <object>
    <title>Headline</title>
    <url>https://example.com</url>
  </object>
</objects>
```

Your items selector would be `objects > object`, the item's `link` selector would be `url`.

Find further information in [ActiveSupport's `Array.to_xml` documentation](https://apidock.com/rails/Hash/to_xml).

</details>

## Set any HTTP header in the request

You can add any HTTP headers to the request to the channel URL.
You can use this to e.g. have Cookie or Authorization information being sent or to overwrite the User-Agent.

<!-- TODO: add ruby example -->

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

The headers provided by the channel will be merged into the global headers.

## Usage with a YAML config file

This step is not required to work with this gem. However, if you're using
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

You can build your feeds like this:

```ruby
require 'html2rss'

myfeed = Html2rss.feed_from_yaml_config('config.yml', 'myfeed')
myotherfeed = Html2rss.feed_from_yaml_config('config.yml', 'myotherfeed')
```

Find a full example of a `config.yml` at [`spec/config.test.yml`](https://github.com/gildesmarais/html2rss/blob/master/spec/config.test.yml).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gildesmarais/html2rss.

## Releasing a new version

1. `git pull`
2. increase version in `lib/html2rss/version.rb`
3. `bundle`
4. commit the changes
5. `git tag v....`
6. [`standard-changelog -f`](https://github.com/conventional-changelog/conventional-changelog/tree/master/packages/standard-changelog)
7. `git add CHANGELOG.md && git commit --amend`
8. `git tag v.... -f`
9. `git push && git push --tags`
