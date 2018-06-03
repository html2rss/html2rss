# Html2rss

[![Build Status](https://travis-ci.org/gildesmarais/html2rss.svg?branch=master)](https://travis-ci.org/gildesmarais/html2rss)

Request and convert an HTML document to an RSS feed via a config object.
The config contains the URL to scrape and the selectors needed to extract
the required information. This gem provides some extractors (e.g. extract
the information from an HTML attribute).

Please always check the website's Terms of Service before if its allowed to
scrape their content!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'html2rss'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install html2rss

## Usage

## Usage with a YAML file

Create a YAML config file. Find an example at `rspec/config.test.yml`.

`Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')` returns

an `RSS:Rss` object.

## Usage in a web application

Find a minimal Sintra app which exposes your feeds to HTTP endpoints here:
[gildesmarais/html2rss-web](https://github.com/gildesmarais/html2rss-web)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gildesmarais/html2rss.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
