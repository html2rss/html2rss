# frozen_string_literal: true

RSpec.describe Html2rss::JsonFeedBuilder do
  subject(:feed_hash) { described_class.new(channel:, articles:).call }

  let(:channel) do
    instance_double(
      Html2rss::RssBuilder::Channel,
      title: 'Feed title',
      url: Html2rss::Url.sanitize('https://example.com'),
      description: 'Feed description',
      language: 'en',
      image: nil,
      author: nil
    )
  end
  let(:articles) do
    [
      Html2rss::RssBuilder::Article.new(id: 'with-content', title: 'Visible', url: 'https://example.com/1'),
      Html2rss::RssBuilder::Article.new(id: 'without-content', url: 'https://example.com/2')
    ]
  end

  it 'filters out items that cannot satisfy the JSON Feed content requirement', :aggregate_failures do
    expect(feed_hash[:items].size).to eq(1)
    expect(feed_hash[:items].first[:id]).to eq(Html2rss::RssBuilder::Article.new(id: 'with-content', title: 'Visible', url: 'https://example.com/1').guid)
    expect(feed_hash[:items].first[:content_text]).to eq('Visible')
  end
end
