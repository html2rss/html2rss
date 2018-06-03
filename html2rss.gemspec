lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'html2rss/version'

Gem::Specification.new do |spec|
  spec.name          = 'html2rss'
  spec.version       = Html2rss::VERSION
  spec.authors       = ['Gil Desmarais']
  spec.email         = ['html2rss@desmarais.de']

  spec.summary       = 'Generate RSS feeds by scraping websites by providing a config.'
  spec.description   = 'Create your config object, include the url to scrape,
                        some selectors and get a RSS2 feed in return.'
  spec.homepage      = 'https://github.com/gildesmarais/html2rss'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nokogiri', '~> 1.8'
  spec.add_dependency 'sanitize', '~> 4.6'
  spec.add_dependency 'faraday', '~> 0.15'
  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'vcr', '~> 4.0'
  spec.add_development_dependency 'byebug'
end
