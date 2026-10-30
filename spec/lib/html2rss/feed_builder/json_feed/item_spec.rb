# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::JsonFeed::Item do
  subject(:item_hash) { described_class.new(article).to_h }

  let(:build_article) { ->(**attrs) { Html2rss::Article.new(**attrs) } }
  let(:article) { build_article.call(**attributes) }
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
    expect(item_hash).not_to have_key(:content_text)
    expect(item_hash[:authors]).to eq([{ name: 'Author Name' }])
  end

  it 'maps a plain-text description to content_text', :aggregate_failures do
    article = build_article.call(**attributes, description: 'Plain description without markup')
    hash = described_class.new(article).to_h

    expect(hash[:content_text]).to eq('Plain description without markup')
    expect(hash).not_to have_key(:content_html)
  end

  it 'falls back to content_text when only a title is available', :aggregate_failures do
    article = build_article.call(id: 'article-1', title: 'Sample title', url: 'https://example.com/articles/1')
    hash = described_class.new(article).to_h

    expect(hash[:content_text]).to eq('Sample title')
    expect(hash).not_to have_key(:content_html)
  end

  it 'does not fall back to title when a description is present' do
    article = build_article.call(**attributes, description: 'Only body')

    expect(described_class.new(article).to_h[:content_text]).to eq('Only body')
  end

  it 'returns nil when the article has no usable content' do
    article = build_article.call(id: 'article-1', url: 'https://example.com/articles/1')

    expect(described_class.new(article).to_h).to be_nil
  end

  context 'with a blank author' do
    let(:attributes) { super().merge(author: ' ') }

    it 'omits author values' do
      expect(item_hash).not_to have_key(:authors)
    end
  end

  context 'with an enclosure' do
    let(:attributes) do
      super().merge(
        enclosures: [{ url: Html2rss::Url.sanitize('https://example.com/audio.mp3'), bytes_length: 123,
                       type: 'audio/mpeg' }]
      )
    end

    it 'preserves enclosure size as size_in_bytes', :aggregate_failures do
      attachment = item_hash[:attachments].first

      expect(attachment[:mime_type]).to eq('audio/mpeg')
      expect(attachment[:size_in_bytes]).to eq(123)
    end
  end

  context 'with an enclosure that has no positive size' do
    let(:attributes) do
      super().merge(
        enclosures: [{ url: Html2rss::Url.sanitize('https://example.com/audio.mp3'), bytes_length: 0,
                       type: 'audio/mpeg' }]
      )
    end

    it 'omits size_in_bytes but keeps the attachment', :aggregate_failures do
      expect(item_hash[:attachments]).to eq([{ url: 'https://example.com/audio.mp3', mime_type: 'audio/mpeg' }])
    end
  end

  context 'with an enclosure that has no size' do
    let(:attributes) do
      super().merge(
        enclosures: [{ url: Html2rss::Url.sanitize('https://example.com/audio.mp3'), type: 'audio/mpeg' }]
      )
    end

    it 'omits size_in_bytes' do
      expect(item_hash[:attachments]).to eq([{ url: 'https://example.com/audio.mp3', mime_type: 'audio/mpeg' }])
    end
  end

  context 'with mixed inline text and markup' do
    let(:attributes) { super().merge(description: 'Plain <b>bold</b> text') }

    it 'maps the description to content_html' do
      expect(item_hash[:content_html]).to eq('Plain <b>bold</b> text')
    end
  end

  context 'with a plain identifier and url' do
    it 'serializes id and url as strings', :aggregate_failures do
      expect(item_hash[:id]).to eq(article.guid)
      expect(item_hash[:url]).to eq('https://example.com/articles/1')
    end
  end

  context 'without enclosures' do
    it 'omits attachments' do
      expect(item_hash).not_to have_key(:attachments)
    end
  end

  context 'with categories' do
    let(:attributes) { super().merge(categories: ['News', ' Tech ']) }

    it 'maps categories to tags' do
      expect(item_hash[:tags]).to eq(%w[News Tech])
    end
  end

  context 'without categories' do
    it 'omits tags' do
      expect(item_hash).not_to have_key(:tags)
    end
  end

  context 'with optional article fields' do
    let(:attributes) do
      super().merge(
        url: nil, image: 'https://example.com/cover.jpg', published_at: Time.utc(2024, 1, 2, 3, 4, 5)
      )
    end

    it 'maps image and published date and omits a missing url', :aggregate_failures do
      expect(item_hash).not_to have_key(:url)
      expect(item_hash[:image]).to eq('https://example.com/cover.jpg')
      expect(item_hash[:date_published]).to eq('2024-01-02T03:04:05+00:00')
    end
  end

  context 'without optional article fields' do
    let(:attributes) { { id: 'article-1', title: 'Sample title', url: 'https://example.com/articles/1' } }

    it 'omits image, date, author and tags', :aggregate_failures do
      expect(item_hash.keys).to contain_exactly(:id, :url, :title, :content_text)
    end
  end
end
