# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'html2rss/version'

Gem::Specification.new do |spec|
  spec.name          = 'html2rss'
  spec.version       = Html2rss::VERSION
  spec.authors       = ['Gil Desmarais']
  spec.email         = ['html2rss@desmarais.de']

  spec.summary       = 'Returns an RSS::Rss object by scraping a URL.'
  spec.description   = 'Give the URL to scrape and some CSS selectors. Get a RSS::Rss instance in return.'
  spec.homepage      = 'https://github.com/html2rss/html2rss'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    spec.metadata['changelog_uri'] = 'https://github.com/html2rss/html2rss/releases'
    spec.metadata['rubygems_mfa_required'] = 'true'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
          'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|support|docs|.github|.yardoc)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'addressable', '~> 2.7'
  spec.add_dependency 'faraday', '> 2.0.1', '< 3.0'
  spec.add_dependency 'faraday-follow_redirects'
  spec.add_dependency 'kramdown'
  spec.add_dependency 'mime-types', '> 3.0'
  spec.add_dependency 'nokogiri', '>= 1.10', '< 2.0'
  spec.add_dependency 'regexp_parser'
  spec.add_dependency 'reverse_markdown', '~> 2.0'
  spec.add_dependency 'rss'
  spec.add_dependency 'sanitize', '~> 6.0'
  spec.add_dependency 'thor'
  spec.add_dependency 'tzinfo'
  spec.add_dependency 'zeitwerk'
end
