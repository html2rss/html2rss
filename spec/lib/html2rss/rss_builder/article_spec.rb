# frozen_string_literal: true

RSpec.describe Html2rss::RssBuilder::Article do
  subject(:instance) { described_class.new(**options) }

  let(:options) { { title: 'Sample instance', url: 'http://example.com', description: 'By John Doe' } }

  describe '#initialize' do
    it 'stores the options as a hash' do
      expect(instance.instance_variable_get(:@to_h)).to eq(options)
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
    before do
      allow(Html2rss::Rendering::DescriptionBuilder).to receive(:new).and_call_original
      instance.description
    end

    it 'calls the DescriptionBuilder' do
      expect(Html2rss::Rendering::DescriptionBuilder).to have_received(:new)
        .with(base: 'By John Doe', title: 'Sample instance', url: instance.url, enclosures: [], image: nil)
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

  describe '.remove_pattern_from_start' do
    it 'removes the pattern when it is within the specified range' do
      original_text = 'Hello world! Start here.'
      pattern = 'world!'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq('Hello  Start here.')
    end

    it 'does not remove the pattern when it is outside the specified range' do
      original_text = 'This is a test. Remove this part.'
      pattern = 'part'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern, end_of_range: 10)
      expect(sanitized_text).to eq(original_text)
    end

    it 'returns the original text if the pattern is not found' do
      original_text = 'No match here.'
      pattern = 'missing'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(original_text)
    end

    it 'returns the original text if the text is empty' do
      original_text = ''
      pattern = 'any'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(original_text)
    end

    it 'removes pattern at the beginning of the text' do
      original_text = 'pattern should be removed from start'
      pattern = 'pattern'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(' should be removed from start')
    end

    it 'handles pattern appearing multiple times in the text' do
      original_text = 'Repeat pattern and again pattern in text.'
      pattern = 'pattern'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq('Repeat  and again pattern in text.')
    end
  end

  describe '.contains_html?' do
    it 'returns true for simple HTML tags' do
      expect(described_class.contains_html?('<div>')).to be(true)
    end

    it 'returns true for HTML tags with attributes' do
      expect(described_class.contains_html?('<a href="https://example.com">')).to be(true)
    end

    it 'returns true for nested HTML tags' do
      expect(described_class.contains_html?('<div><span>Content</span></div>')).to be(true)
    end

    it 'returns false for text without HTML tags' do
      expect(described_class.contains_html?('Just some text')).to be(false)
    end

    it 'returns false for text with angle brackets but no tags' do
      expect(described_class.contains_html?('2 < 3 > 1')).to be(false)
    end

    it 'returns true for self-closing HTML tags' do
      expect(described_class.contains_html?('<br/>')).to be(true)
    end

    it 'returns false for empty string' do
      expect(described_class.contains_html?('')).to be(false)
    end
  end
end
