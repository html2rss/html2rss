# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::AttributeSelector do
  describe '#dispatch_select' do
    subject(:attribute_selector) { described_class.new(categories_extractor:) }

    let(:categories_extractor) { instance_double(Html2rss::Selectors::CategoriesExtractor) }
    let(:response) do
      Html2rss::RequestService::Response.new(
        url: 'http://example.com',
        headers: { 'content-type' => 'text/html' },
        body: <<~HTML
          <html><body>
            <article><h1>episode</h1><audio src="/media/episode.mp3"></audio></article>
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
      value = attribute_selector.dispatch_select(:enclosure, scope:, config: enclosure_config)

      expect(value[:url].to_s).to eq('http://example.com/media/episode.mp3')
      expect(value[:type]).to eq('audio/mpeg')
    end

    it 'delegates categories to CategoriesExtractor', :aggregate_failures do
      allow(categories_extractor).to receive(:select_categories).and_return(%w[News])

      expect(attribute_selector.dispatch_select(:categories, scope:, config: %i[tag]))
        .to eq(%w[News])
      expect(categories_extractor).to have_received(:select_categories)
        .with(category_selectors: %i[tag], scope:)
    end
  end

  describe '#wrap_enclosure_value' do
    subject(:attribute_selector) { described_class.new }

    it 'keeps a single enclosure hash as one list entry' do
      enclosure = { url: 'http://example.com/a.mp3', type: 'audio/mpeg' }

      expect(attribute_selector.wrap_enclosure_value(enclosure)).to eq([enclosure])
    end
  end

  describe 'URL helpers' do
    subject(:attribute_selector) { described_class.new }

    let(:anchor) { Nokogiri::HTML('<a class="card" href="/posts/first">First</a>').at_css('a') }

    it 'detects anchors and resolves fallback item URLs', :aggregate_failures do
      expect(attribute_selector.anchor_element?(anchor)).to be(true)
      expect(attribute_selector.fallback_url_selector?(:url, nil, anchor)).to be(true)
      expect(attribute_selector.default_item_url(anchor, 'http://example.com').to_s)
        .to eq('http://example.com/posts/first')
    end
  end
end
