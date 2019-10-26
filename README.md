![html2rss logo](https://github.com/gildesmarais/html2rss/raw/master/support/logo.png)

[![Build Status](https://travis-ci.org/gildesmarais/html2rss.svg?branch=master)](https://travis-ci.org/gildesmarais/html2rss)
[![Gem Version](https://badge.fury.io/rb/html2rss.svg)](http://rubygems.org/gems/html2rss/)
[API docs on RubyDoc.info](https://www.rubydoc.info/gems/html2rss)

Request HTML from an URL and transform it to a Ruby RSS 2.0 object.

**Are you searching for a ready to use "website to RSS" solution?**
[Check out `html2rss-web`!](https://github.com/gildesmarais/html2rss-web)

Each website needs a _feed config_ which contains the URL to scrape and
CSS selectors to extract the required information (like title, URL, ...).
This gem provides [extractors](https://github.com/gildesmarais/html2rss/blob/master/lib/html2rss/item_extractors) (e.g. extract the information from an HTML attribute)
and chainable [post processors](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/attribute_post_processors) to make information retrieval even easier.

## Installation

Add this line to your application's Gemfile: `gem 'html2rss'`  
Then execute: `bundle`

```ruby
rss =
  Html2rss.feed(
    channel: { title: 'StackOverflow: Hot Network Questions', url: 'https://stackoverflow.com/questions' },
    selectors: {
      items: { selector: '#hot-network-questions > ul > li' },
      title: { selector: 'a' },
      link: { selector: 'a', extractor: 'href' }
    }
  )

puts rss.to_s
```

## Usage with a YAML config file

Create a YAML config file. Find an example at [`rspec/config.test.yml`](https://github.com/gildesmarais/html2rss/blob/master/spec/config.test.yml).

`Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')` returns

an `RSS:Rss` object.

**Too complicated?** See [`html2rss-configs`](https://github.com/gildesmarais/html2rss-configs) for ready-made feed configs!

## Scraping JSON

Since 0.5.0 it is possible to scrape and process JSON.

Adding `json: true` to the channel config will convert the JSON response to XML.

Feed config:

```yaml
channel:
  url: https://example.com
  title: "Example with JSON"
  json: true
# ...
```

Under the hood it uses ActiveSupport's [`Hash.to_xml`](https://apidock.com/rails/Hash/to_xml) core extension for the JSON to XML conversion.

### Conversion of JSON objects

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

### Conversion of JSON arrays

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

## Set any HTTP header in the request

You can add any HTTP headers to the request to the channel URL.
You can use this to e.g. have Cookie or Authorization information being sent or to overwrite the User-Agent.

```yaml
channel:
  url: https://example.com
  title: "Example with http headers"
  headers:
    "User-Agent": "html2rss-request"
    "X-Something": "Foobar"
    "Authorization": "Token deadbea7"
    "Cookie": "monster=MeWantCookie"
# ...
```

The headers provided by the channel will be merged into the global headers.

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
