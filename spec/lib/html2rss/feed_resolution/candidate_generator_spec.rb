# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::CandidateGenerator do
  let(:entry_url) { 'https://example.com/' }
  let(:html) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      </head>
      <body>
        <header><a href="/blog">Blog</a></header>
        <nav><a href="/news">News</a></nav>
        <main>
          <a href="/about">About</a>
        </main>
      </body>
      </html>
    HTML
  end
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute(entry_url),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  it 'keeps one feed slot and listing nav without feed-path starvation', :aggregate_failures do
    urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

    expect(urls.grep(%r{/feed(?:\.xml)?\z|/rss(?:\.xml)?\z})).to eq(['https://example.com/feed.xml'])
    expect(urls).to include('https://example.com/blog').and have_attributes(size: be <= 5)
    expect(urls).not_to include('https://example.com/')
  end

  it 'returns only the feed slot when max is 1' do
    urls = described_class.call(entry_url:, response:, max: 1).map(&:to_s)

    expect(urls).to eq(['https://example.com/feed.xml'])
  end

  it 'uses cluster primary links when list cannot group isolated class cards', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <section>
          <nav><a href="/news/alpha-sidebar-notes">Alpha sidebar notes extra words here</a></nav>
          <div class="card-item">
            <a href="javascript:void(0)">Share</a>
            <h2><a href="/posts/alpha-release">Alpha release notes for the first card</a></h2>
            <p>Description text for the first clustered card goes here extra.</p>
          </div>
        </section>
        <section>
          <nav><a href="/news/beta-sidebar-notes">Beta sidebar notes extra words here</a></nav>
          <div class="card-item">
            <a href="mailto:ed@example.com">Email</a>
            <h2><a href="/posts/beta-release">Beta release notes for the second card</a></h2>
            <p>Description text for the second clustered card goes here extra.</p>
          </div>
        </section>
        <section>
          <nav><a href="/news/gamma-sidebar-notes">Gamma sidebar notes extra words here</a></nav>
          <div class="card-item">
            <a href="javascript:void(0)">Share</a>
            <h2><a href="/posts/gamma-release">Gamma release notes for the third card</a></h2>
            <p>Description text for the third clustered card goes here extra.</p>
          </div>
        </section>
      </body>
      </html>
    HTML
    response = Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute(entry_url),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )

    urls = described_class.call(entry_url:, response:, max: 8).map(&:to_s)

    expect(urls).to include(
      'https://example.com/posts/alpha-release',
      'https://example.com/posts/beta-release'
    )
    expect(urls.grep(/javascript:|mailto:/)).to be_empty
  end

  context 'when the response is not HTML' do
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '{"items":[]}',
        url: Html2rss::Url.from_absolute(entry_url),
        headers: { 'content-type' => 'application/json' },
        status: 200
      )
    end

    it 'offers only listing paths without a feed slot or nav seeds' do
      urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

      expect(urls).to eq(%w[https://example.com/news https://example.com/blog
                            https://example.com/releases https://example.com/changelog])
    end
  end

  context 'with ranked navigation, duplicates and foreign links' do
    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <body>
          <header>
            <a href="/stories/launch-party">Launch party</a>
            <a href="#top">Top</a>
            <a href="/about-us">About</a>
            <a href="https://other.example.net/category/elsewhere">Elsewhere</a>
          </header>
          <nav>
            <a href="/category/tech">Tech</a>
            <a href="/category/tech">Tech again</a>
          </nav>
        </body>
        </html>
      HTML
    end

    it 'orders destinations by rank, drops unranked and foreign links, and dedupes', :aggregate_failures do
      urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

      expect(urls).to eq(%w[https://example.com/feed https://example.com/category/tech
                            https://example.com/stories/launch-party https://example.com/news
                            https://example.com/blog])
    end

    it 'caps listing seeds at max minus the feed slot' do
      urls = described_class.call(entry_url:, response:, max: 3).map(&:to_s)

      expect(urls).to eq(%w[https://example.com/feed https://example.com/category/tech
                            https://example.com/stories/launch-party])
    end

    it 'defaults the candidate budget to DEFAULT_MAX when max is omitted', :aggregate_failures do
      expected = described_class.call(entry_url:, response:, max: 5)

      expect(described_class.call(entry_url:, response:)).to eq(expected)
      expect(described_class.new(entry_url:, response:).call).to eq(expected)
    end

    context 'when the entry page is itself linked with a fragment' do
      let(:entry_url) { 'https://example.com/category/tech' }

      it 'does not offer the entry document as a candidate' do
        urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

        expect(urls.grep(%r{category/tech(#|\z)})).to be_empty
      end
    end
  end
end
