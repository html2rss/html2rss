# frozen_string_literal: true

RSpec.describe Html2rss::Recon::Result do
  subject(:result) { recon_result(verdict: :build, native_feed: nil) }

  it 'provides helper predicate methods per verdict', :aggregate_failures do
    {
      build: [true, false, false],
      defer: [false, true, false],
      drop: [false, false, true]
    }.each do |verdict, expected|
      built = recon_result(verdict:)
      expect([built.build?, built.defer?, built.drop?]).to eq(expected)
    end
  end

  it 'reports a native feed only when one is present', :aggregate_failures do
    expect(result.native_feed?).to be(false)
    expect(recon_result(verdict: :defer, native_feed: 'https://example.com/feed').native_feed?).to be(true)
  end

  it 'serializes every field to a plain hash' do
    built = recon_result(
      verdict: :defer,
      requested_url: Html2rss::Url.from_absolute('https://example.com/blog'),
      final_url: Html2rss::Url.from_absolute('https://example.com/blog/'),
      native_feed: Html2rss::Url.from_absolute('https://example.com/feed'),
      scheme_downgrade: true,
      notes: ['html_bytes=1024']
    )

    expect(built.to_h).to eq(
      requested_url: 'https://example.com/blog',
      final_url: 'https://example.com/blog/',
      status: 200,
      verdict: :defer,
      native_feed: 'https://example.com/feed',
      surface_category: 'article_listing',
      articles_count: 3,
      scheme_downgrade: true,
      notes: ['html_bytes=1024'],
      html_bytesize: 1000
    )
  end

  it 'omits nil fields from the hash', :aggregate_failures do
    hash = recon_result(verdict: :drop, status: nil, surface_category: nil, html_bytesize: nil).to_h

    expect(hash).not_to include(:status, :native_feed, :surface_category, :html_bytesize)
    expect(hash).to include(verdict: :drop, scheme_downgrade: false)
  end
end
