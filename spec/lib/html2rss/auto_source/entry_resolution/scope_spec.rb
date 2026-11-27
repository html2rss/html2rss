# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::EntryResolution::Scope do
  def url(path) = Html2rss::Url.from_absolute("https://example.com#{path}")

  describe '.[]' do
    it 'resolves names and instances and rejects unknown ones', :aggregate_failures do
      expect(described_class['site']).to be(described_class::ALL.fetch(:site))
      expect(described_class[:section]).to be(described_class::DEFAULT)
      expect { described_class['world'] }.to raise_error(Html2rss::InvalidOption, /scope: "world"/)
    end
  end

  describe '#covers?' do
    {
      '/politik/' => { in: %w[/politik/ /politik/feed.xml /politik/wahl/],
                       out: %w[/ /feed.xml /politik-extra/ /news/] },
      '/news/world' => { in: %w[/news/world /news/world/eu /news/world/feed], out: %w[/news/ /news/worldwide /feed] },
      '/inland/index.html' => { in: %w[/inland/ /inland/index~atom.xml], out: %w[/ /inlandx/ /ausland/] }
    }.each do |entry, paths|
      it "limits an entry at #{entry} to its directory", :aggregate_failures do
        scope = described_class::DEFAULT

        paths.fetch(:in).each { expect(scope.covers?(url(entry), url(_1))).to be(true), _1 }
        paths.fetch(:out).each { expect(scope.covers?(url(entry), url(_1))).to be(false), _1 }
      end
    end

    it 'covers the whole site for a root entry or the site scope', :aggregate_failures do
      expect(described_class::DEFAULT.covers?(url('/'), url('/feed.xml'))).to be(true)
      bare = Html2rss::Url.from_absolute('https://example.com')

      expect(described_class::DEFAULT.covers?(bare, url('/news'))).to be(true)
      expect(described_class['site'].covers?(url('/politik/'), url('/feed.xml'))).to be(true)
    end
  end
end
