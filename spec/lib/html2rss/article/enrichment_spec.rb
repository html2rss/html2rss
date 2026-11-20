# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable-next RSpec/ExampleLength -- stubbed HTTP setup
RSpec.describe Html2rss::Article::Enrichment do
  let(:full_html) { File.read('spec/fixtures/enrichment/article_full.html') }
  let(:meta_html) { File.read('spec/fixtures/enrichment/article_meta.html') }
  let(:policy) { Html2rss::RequestService::Policy.new(max_requests: 1) }
  let(:session) do
    context = Html2rss::RequestService::Context.new(
      url: 'https://example.com/news', policy:,
      budget: Html2rss::RequestService::Budget.new(max_requests: 1)
    )
    Html2rss::RequestSession.new(context:, strategy: :default)
  end

  def article(path, **fields)
    Html2rss::Article.new(url: "https://example.com/#{path}", title: path, id: path, **fields)
  end

  def stub_page(path, body, status: 200)
    stub_request(:get, "https://example.com/#{path}")
      .to_return(status:, body:, headers: { 'Content-Type' => 'text/html' })
  end

  describe '.call' do
    it 'fills only the missing fields from JSON-LD and keeps listing values', :aggregate_failures do
      stub_page('a', full_html)
      listed = article('a', author: 'Listing Author', description: 'Listing description')
      result = described_class.call([listed], request_session: session)
      filled = result.articles.first

      expect(filled.author).to eq('Listing Author')
      expect(filled.published_at.iso8601).to eq('2024-05-06T07:08:09+00:00')
      expect(filled.image.to_s).to eq('https://example.com/img/page.jpg')
      expect(filled.description).to eq('Listing description')
      expect(filled.title).to eq('a')
      expect(result.tally).to eq(enriched: 1)
    end

    it 'falls back to meta tags and resolves a relative image', :aggregate_failures do
      stub_page('m', meta_html)
      filled = described_class.call([article('m')], request_session: session).articles.first

      expect(filled.author).to eq('Meta Author')
      expect(filled.image.to_s).to eq('https://example.com/img/og.jpg')
      expect(filled.published_at.iso8601).to eq('2024-03-02T10:00:00+00:00')
    end

    it 'does not fetch an article that already has every field', :aggregate_failures do
      complete = article('c', author: 'A', image: 'https://example.com/i.jpg', published_at: '2020-01-01')
      result = described_class.call([complete], request_session: session)

      expect(result.articles).to eq([complete])
      expect(WebMock).not_to have_requested(:get, 'https://example.com/c')
    end

    it 'honours the cap and leaves later items unfetched', :aggregate_failures do
      stub_page('x1', full_html)
      stub_page('x2', full_html)
      result = described_class.call([article('x1'), article('x2'), article('x3')], request_session: session,
                                                                                   max_fetches: 2)

      expect(result.tally).to eq(enriched: 2)
      expect(result.articles.last.author).to be_nil
      expect(WebMock).not_to have_requested(:get, 'https://example.com/x3')
    end

    it 'clamps max_fetches to the hard maximum' do
      (1..12).each { stub_page("h#{_1}", full_html) }
      described_class.call((1..12).map { article("h#{_1}") }, request_session: session, max_fetches: 99)

      expect(WebMock).to have_requested(:get, %r{example\.com/h\d+}).times(described_class::MAX_FETCHES)
    end

    it 'counts a failed fetch, keeps the item and continues', :aggregate_failures do
      stub_page('bad', 'denied', status: 403)
      stub_page('ok', full_html)
      bad = article('bad')
      result = described_class.call([bad, article('ok')], request_session: session)

      expect(result.articles.first).to equal(bad)
      expect(result.tally).to eq(enriched: 1, enrich_failed: 1)
    end

    it 'counts a non-html response as failed' do
      stub_request(:get, 'https://example.com/j')
        .to_return(body: '{}', headers: { 'Content-Type' => 'application/json' })
      result = described_class.call([article('j')], request_session: session)

      expect(result.tally).to eq(enrich_failed: 1)
    end

    it 'counts an off-origin article as failed and cross-origin skipped without a request', :aggregate_failures do
      off = Html2rss::Article.new(url: 'https://other.example.org/p', title: 't', id: 'p')
      result = described_class.call([off], request_session: session)

      expect(result.tally).to eq(enrich_failed: 1, enrich_skipped_cross_origin: 1)
      expect(WebMock).not_to have_requested(:get, 'https://other.example.org/p')
    end

    it 'never exceeds the listing budget plus max_fetches in total requests' do
      (1..5).each { stub_page("t#{_1}", full_html) }
      stub_request(:get, 'https://example.com/news')
        .to_return(body: '<html></html>', headers: { 'Content-Type' => 'text/html' })
      session.fetch_initial_response
      described_class.call((1..5).map { article("t#{_1}") }, request_session: session, max_fetches: 3)

      expect(WebMock).to have_requested(:get, %r{example\.com/}).times(policy.max_requests + 3)
    end
  end

  it 'bounds a build at the policy ceiling plus the enrichment allowance' do
    expect(described_class::MAX_TOTAL_REQUESTS).to eq(Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING + 10)
  end
end
