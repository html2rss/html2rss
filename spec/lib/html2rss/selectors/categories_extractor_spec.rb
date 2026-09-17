# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::CategoriesExtractor do
  let(:selectors_config) do
    {
      items: { selector: 'article', enhance: false },
      category: { selector: '.category' },
      tags: { selector: '.tags a', extractor: 'text' },
      categories: %i[category tags]
    }
  end
  let(:response) do
    Html2rss::RequestService::Response.new(
      url: 'http://example.com',
      headers: { 'content-type' => 'text/html' },
      body: <<~HTML
        <html><body>
          <article>
            <span class="category">News</span>
            <div class="tags"><a href="/t/ruby">Ruby</a><a href="/t/rss">RSS</a></div>
          </article>
        </body></html>
      HTML
    )
  end
  let(:scope) do
    scraper = Html2rss::Selectors.new(response, selectors: selectors_config, time_zone: 'UTC')
    Html2rss::Selectors::ItemScope.new(
      item: response.parsed_body.at_css('article'),
      base_url: response.url,
      scraper:,
      time_zone: 'UTC'
    )
  end

  describe '.select_categories' do
    it 'flattens single- and multi-node category selectors into discrete strings' do
      expect(described_class.select_categories(category_selectors: %i[category tags], scope:))
        .to eq(%w[News Ruby RSS])
    end

    it 'returns an empty list when a referenced selector is missing' do
      expect(described_class.select_categories(category_selectors: %i[missing], scope:)).to eq([])
    end
  end
end
