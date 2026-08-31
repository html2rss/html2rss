# frozen_string_literal: true

RSpec.describe Html2rss::ReconResult do
  subject(:result) do
    described_class.new(
      requested_url: Html2rss::Url.from_absolute('https://example.com/blog'),
      final_url: Html2rss::Url.from_absolute('https://example.com/blog/'),
      status: 200,
      verdict: :build,
      native_feed: nil,
      surface_category: Html2rss::SurfaceCategory.coerce(:article_list),
      articles_count: 10,
      scheme_downgrade: false,
      notes: ['html_bytes=1024'],
      redirect_chain: ['https://example.com/blog', 'https://example.com/blog/'],
      html_bytesize: 1024
    )
  end

  it 'provides helper predicate methods', :aggregate_failures do
    expect(result.build?).to be(true)
    expect(result.defer?).to be(false)
    expect(result.drop?).to be(false)
    expect(result.has_native_feed?).to be(false)
  end

  it 'serializes to hash cleanly' do # rubocop:disable RSpec/ExampleLength
    expect(result.to_h).to include(
      requested_url: 'https://example.com/blog',
      final_url: 'https://example.com/blog/',
      status: 200,
      verdict: :build,
      articles_count: 10
    )
  end
end
