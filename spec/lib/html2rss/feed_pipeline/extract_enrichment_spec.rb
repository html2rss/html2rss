# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline, '#extract' do
  let(:listing) do
    <<~HTML
      <html><body>
        <article><a href="/2023/01/02/dated-story">Dated story</a></article>
        <article><a href="/offsite">Off-site</a></article>
      </body></html>
    HTML
  end
  let(:enrich) { { article_metadata: true } }
  let(:config) do
    {
      strategy: :default,
      channel: { url: 'https://example.com/news' },
      request: { max_requests: 1 },
      enrich:,
      selectors: { items: { selector: 'article' }, title: { selector: 'a' }, url: { selector: 'a', extractor: 'href' } }
    }.compact
  end
  let(:article_html) { File.read('spec/fixtures/enrichment/article_full.html') }

  def stub_html(url, body, status: 200)
    stub_request(:get, url).to_return(status:, body:, headers: { 'Content-Type' => 'text/html' })
  end

  before do
    stub_html('https://example.com/news', listing)
    stub_html('https://example.com/2023/01/02/dated-story', article_html)
    stub_html('https://example.com/offsite', 'nope', status: 500)
  end

  it 'lets the article-page date beat the URL-path date and reports counts', :aggregate_failures do
    outcome, result = described_class.new(config).to_outcome_and_result
    dated = outcome.articles.find { _1.url.path.include?('dated') }

    expect(dated.published_at.iso8601).to eq('2024-05-06T07:08:09+00:00')
    expect(dated.author).to eq('Ada Page')
    expect(result.status.to_h).to include(enriched: 1, enrich_failed: 1)
  end

  it 'keeps a failed item and falls back to its URL date when the page has none', :aggregate_failures do
    stub_html('https://example.com/2023/01/02/dated-story', '<html></html>')
    outcome, = described_class.new(config).to_outcome_and_result

    expect(outcome.articles.map { _1.url.path }).to include('/offsite', '/2023/01/02/dated-story')
    expect(outcome.articles.find { _1.url.path.include?('dated') }.published_at.iso8601).to start_with('2023-01-02')
  end

  context 'when the option is absent (default off)' do
    let(:enrich) { nil }

    it 'makes no article fetches and adds no counters', :aggregate_failures do
      _, result = described_class.new(config).to_outcome_and_result

      expect(WebMock).not_to have_requested(:get, %r{example\.com/(2023|offsite)})
      expect(result.status.to_h).not_to include(:enriched, :enrich_failed)
    end
  end
end
