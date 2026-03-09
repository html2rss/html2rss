# frozen_string_literal: true

RSpec.describe Html2rss::JsonFeedBuilder::Item do
  subject(:item_hash) { described_class.new(article).to_h }

  let(:article) { Html2rss::RssBuilder::Article.new(**attributes) }
  let(:attributes) do
    {
      id: 'article-1',
      title: 'Sample title',
      description: '<p>Sample description</p>',
      url: 'https://example.com/articles/1',
      author: 'Author Name'
    }
  end

  it 'serializes an item with html content', :aggregate_failures do
    expect(item_hash[:title]).to eq('Sample title')
    expect(item_hash[:content_html]).to eq('<p>Sample description</p>')
    expect(item_hash[:authors]).to eq([{ name: 'Author Name' }])
  end

  it 'falls back to content_text when only a title is available', :aggregate_failures do
    article = Html2rss::RssBuilder::Article.new(id: 'article-1', title: 'Sample title', url: 'https://example.com/articles/1')

    expect(described_class.new(article).to_h[:content_text]).to eq('Sample title')
    expect(described_class.new(article).to_h).not_to have_key(:content_html)
  end

  it 'returns nil when the article has no usable content' do
    article = Html2rss::RssBuilder::Article.new(id: 'article-1', url: 'https://example.com/articles/1')

    expect(described_class.new(article).to_h).to be_nil
  end

  it 'omits blank author values' do
    article = Html2rss::RssBuilder::Article.new(
      id: 'article-1',
      title: 'Sample title',
      description: '<p>Sample description</p>',
      url: 'https://example.com/articles/1',
      author: ' '
    )

    expect(described_class.new(article).to_h).not_to have_key(:authors)
  end

  it 'preserves enclosure size as size_in_bytes', :aggregate_failures do
    article = Html2rss::RssBuilder::Article.new(
      id: 'article-1',
      title: 'Sample title',
      description: '<p>Sample description</p>',
      url: 'https://example.com/articles/1',
      enclosures: [{ url: Html2rss::Url.sanitize('https://example.com/audio.mp3'), bits_length: 123, type: 'audio/mpeg' }]
    )

    attachment = described_class.new(article).to_h[:attachments].first

    expect(attachment[:mime_type]).to eq('audio/mpeg')
    expect(attachment[:size_in_bytes]).to eq(123)
  end
end
