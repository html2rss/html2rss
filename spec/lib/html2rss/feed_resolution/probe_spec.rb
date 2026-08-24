# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Probe do
  subject(:probe) { described_class.new(request_session: session, origin_url:) }

  let(:origin_url) { 'https://example.com/' }
  let(:candidate_url) { Html2rss::Url.from_absolute('https://example.com/news') }
  let(:session) { instance_double(Html2rss::RequestSession) }

  it 'scores a syndication feed response by item count', :aggregate_failures do
    feed_response = Html2rss::RequestService::Response.new(
      body: <<~XML,
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>News</title>
          <item><title>One</title><link>https://example.com/1</link></item>
          <item><title>Two</title><link>https://example.com/2</link></item>
        </channel></rss>
      XML
      headers: { 'content-type' => 'application/rss+xml' },
      url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
      status: 200
    )
    allow(session).to receive(:follow_up).and_return(feed_response)

    scored = probe.call(candidate_url)

    expect(scored.articles_count).to eq(2)
    expect(scored.score).to eq(Html2rss::FeedResolution::Scorer.score_feed(articles_count: 2))
    expect(scored.url.to_s).to eq('https://example.com/feed.xml')
  end

  it 'scores HTML follow-ups via PageRecon assessment' do
    html_response = Html2rss::RequestService::Response.new(
      body: <<~HTML,
        <!DOCTYPE html><html><body>
          <article><h2><a href="/news/a">Alpha launch notes for spring</a></h2></article>
          <article><h2><a href="/news/b">Beta rollout across regions</a></h2></article>
          <article><h2><a href="/news/c">Gamma docs refresh guides</a></h2></article>
        </body></html>
      HTML
      headers: { 'content-type' => 'text/html' },
      url: candidate_url,
      status: 200
    )
    allow(session).to receive(:follow_up).and_return(html_response)

    scored = probe.call(candidate_url)

    expect(scored).to have_attributes(url: candidate_url, articles_count: be >= 1)
  end

  it 'returns nil when the follow-up raises Html2rss::Error' do
    allow(session).to receive(:follow_up).and_raise(Html2rss::Error, 'denied')

    expect(probe.call(candidate_url)).to be_nil
  end
end

# rubocop:enable RSpec/ExampleLength
