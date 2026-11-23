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

    expected = Html2rss::PageRecon.assess(response: html_response, url: candidate_url)

    expect(scored).to have_attributes(
      url: candidate_url, articles_count: expected.articles_count,
      score: Html2rss::FeedResolution::Scorer.score_assessment(expected)
    )
  end

  it 'follows up on the candidate url for the entry-resolution relation' do
    html_response = Html2rss::RequestService::Response.new(
      body: '<!DOCTYPE html><html><body></body></html>',
      headers: { 'content-type' => 'text/html' },
      url: candidate_url,
      status: 200
    )
    allow(session).to receive(:follow_up).and_return(html_response)

    probe.call(candidate_url)

    expect(session).to have_received(:follow_up).with(
      hash_including(url: candidate_url, relation: :entry_resolution, origin_url: Html2rss::Url.from_absolute(origin_url))
    )
  end

  context 'with the candidate page language' do
    let(:html_response) do
      Html2rss::RequestService::Response.new(
        body: '<!DOCTYPE html><html lang="en"><body><article><h2><a href="/a">Alpha</a></h2></article></body></html>',
        headers: { 'content-type' => 'text/html' },
        url: candidate_url,
        status: 200
      )
    end

    before do
      allow(session).to receive(:follow_up).and_return(html_response)
      allow(Html2rss::Vocabulary).to receive(:[]).and_call_original
    end

    it 'scores under the configured channel language even when the page declares another', :aggregate_failures do
      described_class.new(request_session: session, origin_url:, channel: { language: 'sv' }).call(candidate_url)

      expect(Html2rss::Vocabulary).to have_received(:[]).with('sv').at_least(:once)
      expect(Html2rss::Vocabulary).not_to have_received(:[]).with('en')
    end

    it 'resolves the language per response when none is configured', :aggregate_failures do
      probe.call(candidate_url)

      expect(Html2rss::Vocabulary).to have_received(:[]).with('en').at_least(:once)
      expect(Html2rss::Vocabulary).not_to have_received(:[]).with('sv')
    end
  end

  it 'rejects an origin URL that is not absolute' do
    expect do
      described_class.new(request_session: session, origin_url: '/news')
    end.to raise_error(Html2rss::Url::InvalidUrlError, 'URL must be absolute')
  end

  it 'returns nil when the follow-up raises Html2rss::Error' do
    allow(session).to receive(:follow_up).and_raise(Html2rss::Error, 'denied')

    expect(probe.call(candidate_url)).to be_nil
  end

  it 'propagates contract errors raised by the follow-up' do
    allow(session).to receive(:follow_up).and_raise(Html2rss::RequestService::Context::InvalidError)

    expect { probe.call(candidate_url) }.to raise_error(Html2rss::ContractError)
  end
end

# rubocop:enable RSpec/ExampleLength
