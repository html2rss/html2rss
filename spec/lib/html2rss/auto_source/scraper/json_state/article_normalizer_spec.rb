# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonState::ArticleNormalizer do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:article_url) { Html2rss::Url.from_absolute('https://example.com/a') }

  describe '.normalise' do
    it 'returns nil for non-hash entries' do
      expect([
               described_class.normalise('x', base_url:),
               described_class.normalise(nil, base_url:),
               described_class.normalise([{ title: 'x', url: '/a' }], base_url:)
             ]).to all(be_nil)
    end

    it 'returns nil when neither title nor description is present' do
      expect(described_class.normalise({ url: '/a' }, base_url:)).to be_nil
    end

    it 'keeps the article when only a description is present', :aggregate_failures do
      result = described_class.normalise({ description: 'Desc', url: '/a' }, base_url:)

      expect(result).not_to have_key(:title)
      expect(result[:description]).to eq('Desc')
    end

    it 'keeps the article when only a title is present', :aggregate_failures do
      result = described_class.normalise({ title: 'T', url: '/a' }, base_url:)

      expect(result).not_to have_key(:description)
      expect(result[:title]).to eq('T')
    end

    it 'returns the normalised fields for a complete entry', :aggregate_failures do
      entry = { title: 'T', description: 'D', url: '/a', image: '/i.jpg', publishedAt: '2026-01-01',
                tags: ['x'], id: '42' }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'T', description: 'D', published_at: '2026-01-01', categories: ['x'], id: '42')
      expect(result.values_at(:url, :image).map(&:to_s)).to eq(%w[https://example.com/a https://example.com/i.jpg])
    end

    it 'omits absent optional fields and falls back to the url as id', :aggregate_failures do
      result = described_class.normalise({ title: 'T', url: '/a' }, base_url:)

      expect(result.keys).to contain_exactly(:title, :url, :id)
      expect(result[:id]).to eq('https://example.com/a')
    end

    it 'skips entries whose url is missing or invalid' do
      expect([
               described_class.normalise({ title: 'T' }, base_url:),
               described_class.normalise({ title: 'T', url: ['/a'] }, base_url:),
               described_class.normalise({ title: 'T', url: '  ' }, base_url:)
             ]).to all(be_nil)
    end

    it 'resolves the url from a nested links hash' do
      result = described_class.normalise({ title: 'T', links: { self: { href: '/nested' } } }, base_url:)

      expect(result[:url].to_s).to eq('https://example.com/nested')
    end

    it 'logs and drops an invalid image url', :aggregate_failures do
      allow(Html2rss::Log).to receive(:debug)

      result = described_class.normalise({ title: 'T', url: '/a', image: 'ht tp://x' }, base_url:)

      expect(result).not_to have_key(:image)
      expect(Html2rss::Log).to have_received(:debug)
        .with('JsonState: invalid image URL encountered: url=ht tp://x')
    end
  end

  describe '.string' do
    it 'returns stripped strings' do
      expect(described_class.string('  Hi  ')).to eq('Hi')
    end

    it 'converts numeric values to strings', :aggregate_failures do
      expect(described_class.string(42)).to eq('42')
      expect(described_class.string(1.5)).to eq('1.5')
    end

    it 'returns nil for blank, nil, boolean and collection values', :aggregate_failures do
      [nil, '   ', [], ['x'], { foo: 1 }, true].each do |value|
        expect(described_class.string(value)).to be_nil
      end
    end

    it 'preserves HTML in rendered values' do
      expect(described_class.string({ rendered: '<p>Hi</p>' })).to eq('<p>Hi</p>')
    end

    it 'unwraps each scalar wrapper key', :aggregate_failures do
      expect(described_class.string({ rendered: 'r' })).to eq('r')
      expect(described_class.string({ value: 'v' })).to eq('v')
      expect(described_class.string({ text: 't' })).to eq('t')
    end

    it 'unwraps nested wrappers up to three levels', :aggregate_failures do
      expect(described_class.string({ rendered: { value: { text: 'x' } } })).to eq('x')
      expect(described_class.string({ rendered: { value: { text: { rendered: 'x' } } } })).to be_nil
    end
  end

  describe '.unwrap_scalar' do
    it 'returns scalars unchanged' do
      expect(described_class.unwrap_scalar('a')).to eq('a')
    end

    it 'returns nil for hashes without scalar wrapper keys and for arrays', :aggregate_failures do
      expect(described_class.unwrap_scalar({ foo: 1 })).to be_nil
      expect(described_class.unwrap_scalar(['a'])).to be_nil
    end

    it 'unwraps each scalar wrapper key', :aggregate_failures do
      expect(described_class.unwrap_scalar({ rendered: 'r' })).to eq('r')
      expect(described_class.unwrap_scalar({ value: 'v' })).to eq('v')
      expect(described_class.unwrap_scalar({ text: 't' })).to eq('t')
    end

    it 'stops after three unwraps', :aggregate_failures do
      expect(described_class.unwrap_scalar({ rendered: { value: { text: 'x' } } })).to eq('x')
      expect(described_class.unwrap_scalar({ rendered: { value: { text: { rendered: 'x' } } } })).to be_nil
    end
  end

  describe '.resolve_link' do
    let(:log_key) { 'JsonState: test' }

    it 'resolves relative links against the base url' do
      result = described_class.resolve_link({ url: '/a' }, keys: described_class::URL_KEYS,
                                                           base_url:, log_key:)

      expect(result.to_s).to eq('https://example.com/a')
    end

    it 'falls back to the nested links hash' do
      result = described_class.resolve_link({ links: { href: '/b' } }, keys: described_class::URL_KEYS,
                                                                       base_url:, log_key:)

      expect(result.to_s).to eq('https://example.com/b')
    end

    it 'returns nil for blank or non-scalar values', :aggregate_failures do
      expect(described_class.resolve_link({ url: '  ' }, keys: described_class::URL_KEYS, base_url:, log_key:))
        .to be_nil
      expect(described_class.resolve_link({ url: ['/a'] }, keys: described_class::URL_KEYS, base_url:, log_key:))
        .to be_nil
    end

    it 'logs and returns nil for unparseable urls', :aggregate_failures do
      allow(Html2rss::Log).to receive(:debug)

      result = described_class.resolve_link({ url: 'ht tp://x' }, keys: described_class::URL_KEYS,
                                                                  base_url:, log_key:)

      expect(result).to be_nil
      expect(Html2rss::Log).to have_received(:debug).with('JsonState: test: url=ht tp://x')
    end
  end

  describe '.unwrap_url' do
    it 'returns scalar urls unchanged' do
      expect(described_class.unwrap_url('/a', described_class::URL_KEYS)).to eq('/a')
    end

    it 'unwraps nested url keys up to three levels' do
      expect(described_class.unwrap_url({ self: { href: { href: '/x' } } }, described_class::URL_KEYS)).to eq('/x')
    end

    it 'returns nil when the nesting exceeds three levels' do
      deep = { self: { href: { href: { href: '/x' } } } }

      expect(described_class.unwrap_url(deep, described_class::URL_KEYS)).to be_nil
    end
  end

  describe '.published_at' do
    it 'returns the published timestamp key' do
      expect(described_class.published_at({ publishedAt: '2026-01-02' })).to eq('2026-01-02')
    end

    it 'prefers the published timestamp key over date-suffixed keys' do
      expect(described_class.published_at({ publishedAt: '2026-01-02', updatedOn: '2020' })).to eq('2026-01-02')
    end

    it 'falls back to date-suffixed keys' do
      expect(described_class.published_at({ startsOn: '2026-03-04' })).to eq('2026-03-04')
    end

    it 'ignores non-scalar published values and falls back to date-suffixed keys' do
      expect(described_class.published_at({ publishedAt: { foo: 1 }, startsOn: '2026-03-04' })).to eq('2026-03-04')
    end

    it 'stringifies numeric date-suffixed values' do
      expect(described_class.published_at({ createdAt: 1_700_000_000 })).to eq('1700000000')
    end

    it 'returns nil when no date is present' do
      expect(described_class.published_at({ title: 'x' })).to be_nil
    end
  end

  describe '.suffix_date_value' do
    it 'returns nil for non-hash input', :aggregate_failures do
      expect(described_class.suffix_date_value(nil)).to be_nil
      expect(described_class.suffix_date_value('x')).to be_nil
      expect(described_class.suffix_date_value([{ createdAt: '2020' }])).to be_nil
    end

    it 'returns the first date-suffixed key even after non-date keys' do
      expect(described_class.suffix_date_value({ title: 'x', createdAt: '2020' })).to eq('2020')
    end

    it 'returns numeric date-suffixed values' do
      expect(described_class.suffix_date_value({ createdAt: 1700 })).to eq(1700)
    end

    it 'skips date-suffixed keys holding non-scalar values' do
      expect(described_class.suffix_date_value({ createdAt: { x: 1 }, updatedOn: '2021' })).to eq('2021')
    end

    it 'searches attributes before data', :aggregate_failures do
      expect(described_class.suffix_date_value({ attributes: { createdAt: 'a' }, data: { createdAt: 'd' } }))
        .to eq('a')
      expect(described_class.suffix_date_value({ data: { createdAt: 'd' } })).to eq('d')
    end

    it 'returns nil when no date-suffixed key exists' do
      expect(described_class.suffix_date_value({ title: 'x' })).to be_nil
    end
  end

  describe '.date_suffix_key?' do
    it 'matches snake and camel date suffixes', :aggregate_failures do
      expect(described_class.date_suffix_key?(:createdAt)).to be(true)
      expect(described_class.date_suffix_key?('created_at')).to be(true)
      expect(described_class.date_suffix_key?(:startOn)).to be(true)
      expect(described_class.date_suffix_key?('start_on')).to be(true)
    end

    it 'rejects keys without a date suffix', :aggregate_failures do
      expect(described_class.date_suffix_key?(:title)).to be(false)
      expect(described_class.date_suffix_key?('stat')).to be(false)
      expect(described_class.date_suffix_key?('lesson')).to be(false)
      expect(described_class.date_suffix_key?(:format)).to be(false)
    end

    it 'accepts non-string keys without raising' do
      expect(described_class.date_suffix_key?(1)).to be(false)
    end
  end

  describe '.categories' do
    it 'returns strings from an array' do
      expect(described_class.categories({ tags: %w[News Tech] })).to eq(%w[News Tech])
    end

    it 'returns the values of a hash' do
      expect(described_class.categories({ categories: { a: 'News', b: 'Tech' } })).to eq(%w[News Tech])
    end

    it 'wraps a single string' do
      expect(described_class.categories({ section: 'News' })).to eq(%w[News])
    end

    it 'reads name, title and label from hash elements' do
      expect(described_class.categories({ topics: [{ name: 'N' }, { title: 'T' }, { label: 'L' }] }))
        .to eq(%w[N T L])
    end

    it 'stringifies numeric elements' do
      expect(described_class.categories({ tags: ['News', 7] })).to eq(%w[News 7])
    end

    it 'drops blank and nil elements and removes duplicates' do
      expect(described_class.categories({ tags: ['News', '  ', nil, 'News'] })).to eq(%w[News])
    end

    it 'returns nil when no categories remain', :aggregate_failures do
      expect(described_class.categories({ tags: [] })).to be_nil
      expect(described_class.categories({ tags: 5 })).to be_nil
      expect(described_class.categories({ title: 'x' })).to be_nil
    end
  end

  describe '.identifier' do
    it 'uses the identifier key, stringified' do
      expect(described_class.identifier({ id: 42 }, article_url)).to eq('42')
    end

    it 'accepts alternative identifier keys' do
      expect(described_class.identifier({ guid: 'g-1' }, article_url)).to eq('g-1')
    end

    it 'unwraps a nested identifier hash' do
      expect(described_class.identifier({ id: { uuid: 'u-1' } }, article_url)).to eq('u-1')
    end

    it 'falls back to the article url for missing or blank identifiers', :aggregate_failures do
      expect(described_class.identifier({ title: 'x' }, article_url)).to eq('https://example.com/a')
      expect(described_class.identifier({ id: '  ' }, article_url)).to eq('https://example.com/a')
    end
  end
end
