![html2rss logo](https://github.com/gildesmarais/html2rss/raw/master/support/logo.png)

# html2rss [![Build Status](https://travis-ci.org/gildesmarais/html2rss.svg?branch=master)](https://travis-ci.org/gildesmarais/html2rss) [![Gem Version](https://badge.fury.io/rb/html2rss.svg)](https://badge.fury.io/rb/html2rss)

Request HTML from an URL and transform it to a Ruby RSS 2.0 object.

**Are you searching for a ready to use "website to RSS" solution?**
[Check out `html2rss-web`!](https://github.com/gildesmarais/html2rss-web)

Each website needs a *feed config* which contains the URL to scrape and
CSS selectors to extract the required information (like title, URL, ...).
This gem provides [extractors](https://github.com/gildesmarais/html2rss/blob/master/lib/html2rss/item_extractor.rb) (e.g. extract the information from an HTML attribute)
and chainable [post processors](https://github.com/gildesmarais/html2rss/tree/master/lib/html2rss/attribute_post_processors) to make information retrieval even easier.

## Installation

Add this line to your application's Gemfile: `gem 'html2rss'`
And then execute: `bundle`

```ruby
rss = Html2rss.feed(
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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gildesmarais/html2rss.

## Releasing a new version

1. increase version in `lib/version.rb`
2. `bundle`
3. commit the changes
4. `git tag v....`
5. `git push; git push --tags`
6. update the changelog, commit and push

### Changelog generation

The `CHANGELOG.md` can be generated automatically with [`standard-changelog`](https://github.com/conventional-changelog/conventional-changelog/tree/master/packages/standard-changelog).
