# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::JsonFeed do
  subject(:feed_hash) do
    described_class.new(channel:, articles:, feed_url:, user_comment:).call
  end

  let(:feed_url) { nil }
  let(:user_comment) { nil }
  let(:channel) do
    instance_double(
      Html2rss::Channel,
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
      Html2rss::Article.new(id: 'with-content', title: 'Visible', url: 'https://example.com/1'),
      Html2rss::Article.new(id: 'without-content', url: 'https://example.com/2')
    ]
  end

  it 'filters out items that cannot satisfy the JSON Feed content requirement', :aggregate_failures do
    expect(feed_hash[:items].size).to eq(1)
    expect(feed_hash[:items].first[:id]).to eq(Html2rss::Article.new(id: 'with-content', title: 'Visible',
                                                                     url: 'https://example.com/1').guid)
    expect(feed_hash[:items].first[:content_text]).to eq('Visible')
  end

  context 'with feed_url and user_comment' do
    let(:feed_url) { 'https://example.com/feed.json' }
    let(:user_comment) { 'html2rss V. 1.0 (scrapers: Selectors (1))' }

    it 'includes feed identity and generator comment', :aggregate_failures do
      expect(feed_hash[:feed_url]).to eq(feed_url)
      expect(feed_hash[:user_comment]).to eq(user_comment)
    end
  end

  it 'falls back to Status generator comment when user_comment is omitted' do
    expect(feed_hash[:user_comment]).to eq(
      Html2rss::Status.build(articles:).to_generator_comment
    )
  end
end
