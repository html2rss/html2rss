# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::AttributeSelector do
  describe '#call' do
    subject(:attribute_selector) { described_class.new }

    let(:response) do
      Html2rss::RequestService::Response.new(
        url: 'http://example.com',
        headers: { 'content-type' => 'text/html' },
        body: <<~HTML
          <html><body>
            <article>
              <h1>episode</h1>
              <span class="category">News</span>
              <div class="tags"><a href="/t/ruby">Ruby</a><a href="/t/rss">RSS</a></div>
              <audio src="/media/episode.mp3"></audio>
            </article>
          </body></html>
        HTML
      )
    end
    let(:enclosure_config) do
      { selector: 'audio', extractor: 'attribute', attribute: 'src', content_type: 'audio/mpeg' }
    end
    let(:scope) do
      scraper = Html2rss::Selectors.new(
        response,
        selectors: { items: { selector: 'article', enhance: false }, enclosure: enclosure_config },
        time_zone: 'UTC'
      )
      Html2rss::Selectors::ItemScope.new(
        item: response.parsed_body.at_css('article'),
        base_url: response.url,
        scraper:,
        time_zone: 'UTC'
      )
    end

    it 'extracts enclosure details through the special path', :aggregate_failures do
      value = attribute_selector.call(:enclosure, scope:, config: enclosure_config)

      expect(value[:url].to_s).to eq('http://example.com/media/episode.mp3')
      expect(value[:type]).to eq('audio/mpeg')
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'flattens single- and multi-node category selectors into discrete strings', :aggregate_failures do
      scraper = Html2rss::Selectors.new(
        response,
        selectors: {
          items: { selector: 'article', enhance: false },
          category: { selector: '.category' },
          tags: { selector: '.tags a', extractor: 'text' },
          categories: %i[category tags]
        },
        time_zone: 'UTC'
      )
      cat_scope = Html2rss::Selectors::ItemScope.new(
        item: response.parsed_body.at_css('article'),
        base_url: response.url,
        scraper:,
        time_zone: 'UTC'
      )

      expect(attribute_selector.call(:categories, scope: cat_scope, config: %i[category tags]))
        .to eq(%w[News Ruby RSS])
    end

    it 'returns an empty list when a referenced category selector is missing' do
      scraper = Html2rss::Selectors.new(
        response,
        selectors: { items: { selector: 'article', enhance: false }, categories: %i[missing] },
        time_zone: 'UTC'
      )
      cat_scope = Html2rss::Selectors::ItemScope.new(
        item: response.parsed_body.at_css('article'),
        base_url: response.url,
        scraper:,
        time_zone: 'UTC'
      )

      expect(attribute_selector.call(:categories, scope: cat_scope, config: %i[missing])).to eq([])
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'applies post_process steps on multi-node category extracts', :aggregate_failures do
      selectors_config = {
        items: { selector: 'article', enhance: false },
        tags: {
          selector: '.tags a',
          extractor: 'text',
          post_process: { name: 'gsub', pattern: 'R', replacement: 'r' }
        },
        categories: %i[tags]
      }
      scraper = Html2rss::Selectors.new(response, selectors: selectors_config, time_zone: 'UTC')
      processed_scope = Html2rss::Selectors::ItemScope.new(
        item: response.parsed_body.at_css('article'),
        base_url: response.url,
        scraper:,
        time_zone: 'UTC'
      )

      expect(attribute_selector.call(:categories, scope: processed_scope, config: %i[tags]))
        .to eq(%w[ruby rSS])
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'falls back to the anchor href when url selector is omitted', :aggregate_failures do
      anchor = Nokogiri::HTML('<a class="card" href="/posts/first">First</a>').at_css('a')
      scraper = Html2rss::Selectors.new(
        response,
        selectors: { items: { selector: 'a.card', enhance: false } },
        time_zone: 'UTC'
      )
      anchor_scope = Html2rss::Selectors::ItemScope.new(
        item: anchor,
        base_url: 'http://example.com',
        scraper:,
        time_zone: 'UTC'
      )

      expect(attribute_selector.call(:url, scope: anchor_scope, config: nil).to_s)
        .to eq('http://example.com/posts/first')
    end
  end
end
