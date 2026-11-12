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

    it 'stores no unset input, so a copy with none adds nothing on merge' do
      article = described_class.new(id: 'x', url: 'https://example.com/a')

      expect(article.merge(described_class.new(url: 'https://example.com/a'))).to be(article)
    end

    context 'with enclosures and no declared image' do
      let(:file) { ->(name, type = nil) { { url: Html2rss::Url.from_absolute("https://example.com/#{name}"), type: } } }

      it 'is the first image enclosure when none is declared, which stays an enclosure', :aggregate_failures do
        article = described_class.new(enclosures: [file.call('a.mp3'), file.call('p/1', 'image/png'),
                                                   file.call('b.jpg')])

        expect(article.image.to_s).to eq('https://example.com/p/1')
        expect(article.enclosures.size).to eq(3)
      end

      it 'keeps a declared image, replaces a blank one and has none without an image file', :aggregate_failures do
        expect(described_class.new(image: 'https://example.com/d.jpg', enclosures: [file.call('b.jpg')]).image.to_s)
          .to eq('https://example.com/d.jpg')
        expect(described_class.new(image: '', enclosures: [file.call('b.jpg')]).image.to_s).to eq('https://example.com/b.jpg')
        expect(described_class.new(enclosures: [file.call('a.mp3'), file.call('n.pdf')]).image).to be_nil
      end

      it 'survives a merge with a page copy carrying another image' do
        feed_item = described_class.new(url: 'https://example.com/a', enclosures: [file.call('feed.jpg')])
        page_copy = described_class.new(url: 'https://example.com/a', image: 'https://example.com/card-large.jpg')

        expect(feed_item.merge(page_copy).image.to_s).to eq('https://example.com/feed.jpg')
      end
    end

    it 'accepts every key in PROVIDED_KEYS' do
      attrs = described_class::PROVIDED_KEYS.to_h { |key| [key, key == :enclosures ? [] : 'x'] }
      expect { described_class.new(**attrs) }.not_to raise_error
    end

    it 'reports media items', :aggregate_failures do
      expect(described_class.new(media: true).media?).to be(true)
      expect(described_class.new.media?).to be(false)
    end

    it 'composes the kicker and headline into the title when the caller opts in' do
      article = described_class.new(title: "Ferry\nreturns", kicker: 'Harbor :', compose_title: true)

      expect(article.title).to eq('Harbor: Ferry returns')
    end

    it 'keeps the title verbatim apart from whitespace by default', :aggregate_failures do
      expect(described_class.new(title: '10:00 Budget vote').title).to eq('10:00 Budget vote')
      expect(described_class.new(title: 'Video: Harbor tour').title).to eq('Video: Harbor tour')
      expect(described_class.new(title: "  Ferry\n returns ", kicker: 'Harbor').title).to eq('Ferry returns')
    end

    it 'keeps the composed title across copies and Marshal round-trips', :aggregate_failures do
      article = described_class.new(title: '– Ferry returns', kicker: 'Harbor -', url: 'https://example.com/a',
                                    compose_title: true)

      expect(article.with_url('https://example.com/b').title).to eq('Harbor: Ferry returns')
      expect(Marshal.load(Marshal.dump(article)).title).to eq('Harbor: Ferry returns')
    end

    it 'leaves the title nil when only a kicker is given' do
      expect(described_class.new(kicker: 'Harbor', url: 'https://example.com/a').title).to be_nil
    end

    # rubocop:disable-next RSpec/ExampleLength -- one constructor input per reader
    it 'stores a frozen copy of every non-title input', :aggregate_failures do
      author = +'Ann'
      article = described_class.new(
        id: 'i', author:, description: 'D', url: 'https://example.com/a', image: 'https://example.com/i.jpg',
        guid: ['g'], published_at: '2026-01-02', categories: ['C'], scraper: Html2rss::Selectors,
        enclosures: [{ url: Html2rss::Url.from_absolute('https://example.com/a.mp3') }]
      )
      author << 'e'

      expect(article).to have_attributes(id: 'i', author: 'Ann', description: 'D', categories: ['C'])
      expect(article.scraper).to equal(Html2rss::Selectors)
      expect([article.url, article.image].map(&:to_s)).to eq(%w[https://example.com/a https://example.com/i.jpg])
      expect(article.guid).to eq(Zlib.crc32('g').to_s(36))
      expect(article.published_at.to_s).to start_with('2026-01-02')
      expect(article.enclosures.map { _1.url.to_s }).to eq(['https://example.com/a.mp3'])
    end

    it 'rejects unknown keys' do
      expect { described_class.new(title: 'Sample', unknown_key: 'value') }.to raise_error(ArgumentError)
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

  describe '#with_url' do
    let(:options) { { id: 'a', title: 'Sample instance', url: 'http://example.com/a?utm_term=t', scraper: Object } }

    it 'copies the article with another URL', :aggregate_failures do
      copy = instance.with_url(Html2rss::Url.from_absolute('https://example.com/a'))

      expect(copy.url.to_s).to eq('https://example.com/a')
      expect(copy).to have_attributes(id: 'a', title: 'Sample instance', scraper: Object)
      expect(instance.url.to_s).to eq('http://example.com/a?utm_term=t')
    end
  end

  describe '#merge' do
    let(:options) do
      { id: 'feed-1', title: 'Publisher headline', url: 'https://example.com/a', guid: 'g-1', categories: [],
        description: '', published_at: '2026-11-02T08:00:00Z', scraper: Html2rss::AutoSource::Scraper::NativeFeed }
    end
    let(:page_copy) do
      described_class.new(id: 'card-1', title: 'Kicker: Card headline', url: 'https://example.com/a/',
                          image: 'https://example.com/a.jpg', categories: ['City'], description: 'Card teaser.',
                          published_at: '2026-11-10', scraper: Html2rss::AutoSource::Scraper::Html)
    end

    it 'keeps every field it carries and fills the fields it lacks from the other copy', :aggregate_failures do
      expect(instance.merge(page_copy)).to have_attributes(
        id: 'feed-1', title: 'Publisher headline', guid: instance.guid, published_at: instance.published_at,
        scraper: options[:scraper], description: 'Card teaser.', categories: ['City'], url: instance.url,
        image: page_copy.image
      )
    end

    it 'returns itself when the other copy adds nothing' do
      expect(instance.merge(described_class.new(id: 'x', title: 'Other', url: 'https://example.com/a'))).to be(instance)
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

    it 'passes an http(s) Url through without re-parsing' do
      url = Html2rss::Url.from_absolute('https://example.com/a')

      expect(described_class.new(url:, title: 'T').url).to equal(url)
    end

    it 'still sanitizes a non-http Url so it is not passed through', :aggregate_failures do
      ftp = Html2rss::Url.from_absolute('ftp://example.com/a')

      expect(described_class.new(url: ftp, title: 'T').url.scheme).to eq('ftp')
      expect(described_class.new(url: Html2rss::Url.from_absolute('mailto:a@example.com'), title: 'T').url.scheme)
        .to eq('mailto')
    end

    it 'memoizes the sanitized url', :aggregate_failures do
      article = described_class.new(url: ' https://example.com/a ', title: 'T')

      expect(article.url).to equal(article.url)
      expect(article.url.to_s).to eq('https://example.com/a')
    end

    it 'sanitizes only the url option, not other options' do
      article = described_class.new(url: 'https://example.com/a', description: 'https://other.test/x', title: 'T')

      expect(article.url.to_s).to eq('https://example.com/a')
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
