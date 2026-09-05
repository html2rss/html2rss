# frozen_string_literal: true

RSpec.describe Html2rss::Article do
  subject(:instance) { described_class.new(**options) }

  let(:options) { { title: 'Sample instance', url: 'http://example.com', description: 'By John Doe' } }

  describe '#initialize' do
    it 'exposes the provided options via public readers', :aggregate_failures do
      expect(instance.title).to eq(options[:title])
      expect(instance.url.to_s).to eq("#{options[:url]}/")
      expect(instance.description).to eq(options[:description])
    end

    context 'when unknown options are present' do
      let(:options) { { title: 'Sample instance', url: 'http://example.com', description: 'By John Doe', unknown_key: 'value' } }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'logs a warning' do
        described_class.new(**options)
        expect(Html2rss::Log).to have_received(:warn).with('Article: unknown keys found: unknown_key')
      end
    end
  end

  describe 'Marshal round-trip' do
    let(:options) do
      { id: '1', title: 'Sample', url: 'http://example.com', description: 'Body', scraper: Html2rss::Selectors,
        categories: ['News'], enclosures: [{ url: Html2rss::Url.from_absolute('https://example.com/a.mp3'),
                                             type: 'audio/mpeg', bytes_length: 1 }] }
    end

    # rubocop:disable-next RSpec/ExampleLength -- asserts restored scalars + frozen collections
    it 'restores attributes without NOT_SET sentinel leakage', :aggregate_failures do
      restored = Marshal.load(Marshal.dump(instance))

      expect(restored.title).to eq('Sample')
      expect(restored.description).to include('Body')
      expect(restored.categories).to eq(['News'])
      expect(restored.categories).to be_frozen
      expect(restored.enclosures).to be_frozen
    end

    it 'keeps marshal hooks off the public API' do
      expect(instance.public_methods(false)).not_to include(:marshal_dump, :marshal_load)
    end
  end

  describe 'defensive copies' do
    it 'does not freeze caller-owned option collections', :aggregate_failures do
      categories = ['News']
      article = described_class.new(id: '1', title: 'T', url: 'https://example.com/a', categories:)
      categories << 'Extra'

      expect(article.categories).to eq(['News'])
      expect { article.categories << 'More' }.to raise_error(FrozenError)
    end
  end

  describe '#each' do
    let(:yields) do
      described_class::PROVIDED_KEYS.map do |key|
        [key, instance.public_send(key)]
      end
    end

    it 'yields each PROVIDED_KEY with their values' do
      expect { |b| instance.each(&b) }.to yield_successive_args(*yields)
    end

    it 'returns an Enumerator if no block is given' do
      expect(instance.each).to be_an(Enumerator)
    end

    it 'returns frozen values' do
      instance.each { |value| expect(value).to be_frozen } # rubocop:disable RSpec/IteratedExpectation
    end
  end

  describe '#description' do
    it 'returns the raw extracted description without DescriptionBuilder', :aggregate_failures do
      allow(Html2rss::Html::Rendering::DescriptionBuilder).to receive(:new)

      expect(instance.description).to eq('By John Doe')
      expect(Html2rss::Html::Rendering::DescriptionBuilder).not_to have_received(:new)
    end

    it 'returns nil for a blank description' do
      expect(described_class.new(description: '  ').description).to be_nil
    end
  end

  describe '#url' do
    it 'returns the url if present', :aggregate_failures do
      url = instance.url

      expect(url).to be_a(Html2rss::Url)
      expect(url.to_s).to eq('http://example.com/')
    end

    it 'returns nil if no url is present' do
      instance = described_class.new(title: 'Sample instance')
      expect(instance.url).to be_nil
    end
  end

  describe 'blank scalar normalization' do
    it 'returns nil for a blank title' do
      instance = described_class.new(title: '   ')

      expect(instance.title).to be_nil
    end

    it 'returns nil for a blank author' do
      instance = described_class.new(author: "\n\t")

      expect(instance.author).to be_nil
    end

    it 'returns nil for a blank id' do
      instance = described_class.new(id: ' ')

      expect(instance.id).to be_nil
    end
  end

  describe '#valid?' do
    context 'when url, title, and id are present' do
      let(:options) { { url: 'http://example.com', title: 'Sample Title', id: 'foobar' } }

      it { is_expected.to be_valid }
    end

    context 'when url is missing' do
      let(:options) { { title: 'Sample Title' } }

      it { is_expected.not_to be_valid }
    end

    context 'when title is missing' do
      let(:options) { { url: 'http://example.com' } }

      it { is_expected.not_to be_valid }
    end

    context 'when url, title, and guid are missing' do
      let(:options) { {} }

      it { is_expected.not_to be_valid }
    end
  end

  describe '#guid' do
    it 'returns a unique identifier based on the url and id', :aggregate_failures do
      instance = described_class.new(url: 'http://example.com/article', id: '123')
      expect(instance.guid).to eq('vikwuv')
      expect(instance.guid.encoding).to eq(Encoding::UTF_8)
    end

    it 'returns a different identifier for different urls' do
      instance1 = described_class.new(url: 'http://example.com/article1', id: '123')
      instance2 = described_class.new(url: 'http://example.com/article2', id: '123')
      expect(instance1.guid).not_to eq(instance2.guid)
    end

    it 'returns a different identifier for different ids' do
      instance1 = described_class.new(url: 'http://example.com/article1', id: '123')
      instance2 = described_class.new(url: 'http://example.com/article2', id: '456')
      expect(instance1.guid).not_to eq(instance2.guid)
    end

    it 'returns the same identifier for the same url and id' do
      instance1 = described_class.new(url: 'http://example.com/article', id: '123')
      instance2 = described_class.new(url: 'http://example.com/article', id: '123')
      expect(instance1.guid).to eq(instance2.guid)
    end

    it 'returns the same identifier for the same url and id with different case' do
      instance1 = described_class.new(url: 'http://example.com/article', id: '123')
      instance2 = described_class.new(url: 'http://EXAMPLE.com/article', id: '123')
      expect(instance1.guid).to eq(instance2.guid)
    end
  end

  describe '#deduplication_fingerprint' do
    let(:separator) { described_class::DEDUP_FINGERPRINT_SEPARATOR }

    it 'prefers the sanitized URL combined with the id' do
      article = described_class.new(url: 'http://example.com/article', id: '123')
      expected = [article.url.to_s, '123'].join(separator)

      expect(article.deduplication_fingerprint).to eq(expected)
    end

    it 'falls back to the id when the URL is missing' do
      article = described_class.new(id: 'only-id')

      expect(article.deduplication_fingerprint).to eq('only-id')
    end

    it 'falls back to the guid enriched with metadata', :aggregate_failures do
      article = described_class.new(title: 'Alpha', description: 'Beta', guid: ['custom-guid'])
      expected = [article.guid, article.title, article.description].join(separator)

      expect(article.deduplication_fingerprint).to eq(expected)
    end
  end

  describe '#categories' do
    it 'returns an array of unique and present categories' do
      instance = described_class.new(categories: ['Category 1', '', 'Category 2', 'Category 1 '])
      expect(instance.categories).to eq(['Category 1', 'Category 2'])
    end

    it 'returns an empty array if no categories are present' do
      instance = described_class.new
      expect(instance.categories).to eq([])
    end
  end

  describe '#published_at' do
    it 'returns a Time object if published_at is present and valid' do
      instance = described_class.new(published_at: '2022-01-01T12:00:00Z')
      expect(instance.published_at).to be_a(DateTime)
    end

    it 'returns nil if published_at is not present' do
      instance = described_class.new
      expect(instance.published_at).to be_nil
    end

    it 'returns nil if published_at is invalid' do
      instance = described_class.new(published_at: 'invalid_date')
      expect(instance.published_at).to be_nil
    end
  end
end
