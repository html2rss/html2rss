# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Assessment do
  let(:html) { File.read('spec/fixtures/local_feed_test.html') }
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  let(:item_count) { 7 }
  let(:list_items) do
    (1..item_count).map do |index|
      '<li class="post"><h2>' \
        "<a href=\"/posts/#{index}\">Post title number #{index} with words</a></h2>" \
        "<p>Description text for post #{index} is long enough to count as content here.</p></li>"
    end.join
  end
  let(:list_response) do
    Html2rss::RequestService::Response.new(
      body: '<!DOCTYPE html><html><head><title>Blog</title></head>' \
            "<body><main><ul>#{list_items}</ul></main></body></html>",
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  it 'surface_category_for matches assess without a second extract job' do
    expect(described_class.surface_category_for(response:)).to eq(
      described_class.call(response:).surface_category
    )
  end

  it 'marks feed responses as unsupported_surface via surface_category_for' do
    feed = Html2rss::RequestService::Response.new(
      body: '<rss version="2.0"><channel></channel></rss>',
      url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
      headers: { 'content-type' => 'application/rss+xml' },
      status: 200
    )

    expect(described_class.surface_category_for(response: feed)).to eq(
      :unsupported_surface
    )
  end

  it 'resolves the page language from the channel override over the page declaration', :aggregate_failures do
    english = Html2rss::RequestService::Response.new(
      body: list_response.body.sub('<html', '<html lang="en"'), url: list_response.url,
      headers: { 'content-type' => 'text/html' }, status: 200
    )
    allow(Html2rss::Vocabulary).to receive(:[]).and_call_original
    described_class.call(response: english, channel: { language: 'sv' })

    expect(Html2rss::Vocabulary).to have_received(:[]).with('sv').at_least(:once)
    expect(Html2rss::Vocabulary).not_to have_received(:[]).with('en')
  end

  context 'with more list items than the cheap article limit' do
    let(:item_count) { 12 }

    it 'caps the cheap article count at the fixed AutoSource limit', :aggregate_failures do
      assessment = described_class.call(response: list_response)

      expect(assessment.articles_count).to eq(10)
      expect(assessment.html_response).to be(true)
    end
  end

  it 'reports no cheap articles or drops for a non-HTML, non-feed body', :aggregate_failures do
    plain = Html2rss::RequestService::Response.new(
      body: 'plain text body',
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/plain' },
      status: 200
    )
    assessment = described_class.call(response: plain)

    expect(assessment.articles_count).to eq(0)
    expect(assessment.admission_drops).to eq({})
  end
end

# rubocop:enable RSpec/ExampleLength
