# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::JsonFeed do
  subject(:feed_hash) do
    described_class.new(channel:, articles:, feed_url:, user_comment:).call
  end

  let(:feed_url) { nil }
  let(:user_comment) { 'html2rss V. test (scrapers: none)' }
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

  it 'requires a non-blank user_comment' do
    expect do
      described_class.new(channel:, articles:, user_comment: nil)
    end.to raise_error(ArgumentError, /user_comment/)
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

  describe 'feed_url boundary validation' do
    it 'omits feed_url when nil or blank', :aggregate_failures do
      expect(described_class.new(channel:, articles:, user_comment:, feed_url: nil).call).not_to have_key(:feed_url)
      expect(described_class.new(channel:, articles:, user_comment:, feed_url: '  ').call).not_to have_key(:feed_url)
    end

    it 'normalizes a valid absolute feed_url' do
      payload = described_class.new(
        channel:, articles:, user_comment:, feed_url: 'https://example.com/feed.json'
      ).call

      expect(payload[:feed_url]).to eq('https://example.com/feed.json')
    end

    it 'rejects a relative feed_url' do
      expect do
        described_class.new(channel:, articles:, user_comment:, feed_url: '/relative.json')
      end.to raise_error(ArgumentError, /absolute/)
    end

    it 'rejects a non-string feed_url' do
      expect do
        described_class.new(channel:, articles:, user_comment:, feed_url: :symbol)
      end.to raise_error(ArgumentError, /feed_url must be a String or nil/)
    end
  end
end
