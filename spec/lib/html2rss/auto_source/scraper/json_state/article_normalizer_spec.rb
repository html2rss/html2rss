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

    describe 'kicker' do
      %i[overline kicker kickerText topline dachzeile eyebrow].each do |key|
        it "reads the #{key} field beside the headline" do
          result = described_class.normalise({ title: 'T', url: '/a', key => 'Politics' }, base_url:)

          expect(result[:kicker]).to eq('Politics')
        end
      end

      it 'omits the kicker when the entry has no kicker field' do
        expect(described_class.normalise({ title: 'T', url: '/a' }, base_url:)).not_to have_key(:kicker)
      end

      it 'omits the kicker of a description-only entry so it never becomes the title' do
        result = described_class.normalise({ description: 'D', url: '/a', overline: 'Politics' }, base_url:)

        expect(result).not_to have_key(:kicker)
      end
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

    %i[node fields content item model].each do |wrapper|
      it "reads the article fields from a #{wrapper} wrapper", :aggregate_failures do
        entry = { wrapper => { title: 'T', url: '/a', description: 'D', publishedAt: '2026-01-01', id: '9' } }
        result = described_class.normalise(entry, base_url:)

        expect(result).to include(title: 'T', description: 'D', published_at: '2026-01-01', id: '9')
        expect(result[:url].to_s).to eq('https://example.com/a')
      end
    end

    it 'skips an entry whose author and content objects both carry a title and url' do
      entry = { author: { name: 'Staff', url: '/authors/staff' }, content: { title: 'T', url: '/a' } }

      expect(described_class.normalise(entry, base_url:)).to be_nil
    end

    it 'uses the entry own url and the content title when an author object holds a name and url',
       :aggregate_failures do
      entry = { url: '/a', content: { title: 'T' }, author: { name: 'Staff', url: '/authors/staff' } }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'T')
      expect(result[:url].to_s).to eq('https://example.com/a')
    end

    it 'prefers the entry own url over the url of its content node', :aggregate_failures do
      entry = { url: '/a', content: { title: 'T', url: '/node' }, author: { name: 'Staff', url: '/authors/staff' } }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'T')
      expect(result[:url].to_s).to eq('https://example.com/a')
    end

    it 'keeps the node url when the entry only has an envelope links key', :aggregate_failures do
      entry = { links: { self: { href: '/api/node/article/u1' } },
                attributes: { title: 'Harbor ferry', path: { alias: '/news/harbor-ferry' } } }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'Harbor ferry')
      expect(result[:url].to_s).to eq('https://example.com/news/harbor-ferry')
    end

    it 'prefers the node url over an unrelated sibling links array', :aggregate_failures do
      entry = { node: { title: 'T', url: '/news/harbor' }, links: [{ url: '/tag/a' }] }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'T')
      expect(result[:url].to_s).to eq('https://example.com/news/harbor')
    end

    it 'never turns an author-only entry into an article', :aggregate_failures do
      author = { name: 'Staff', url: '/authors/staff' }

      expect(described_class.normalise({ url: '/a', author: }, base_url:)).to be_nil
      expect(described_class.normalise({ author: }, base_url:)).to include(title: 'Staff')
    end

    it 'reads a JSON:API envelope with attributes and sibling links', :aggregate_failures do
      entry = { id: '7', attributes: { title: 'T', createdAt: '2026-02-02' }, links: { self: '/a' } }
      result = described_class.normalise(entry, base_url:)

      expect(result).to include(title: 'T', published_at: '2026-02-02', id: '7')
      expect(result[:url].to_s).to eq('https://example.com/a')
    end
  end

  describe '.article_sources' do
    it 'returns nil for non-hash entries' do
      expect(described_class.article_sources([{ title: 'T', url: '/a' }])).to be_nil
    end

    it 'accepts Hash subclasses as entries and nodes', :aggregate_failures do
      node = Class.new(Hash)[title: 'T', url: '/a']
      entry = Class.new(Hash)[node:, flag: true]

      expect(described_class.article_sources(entry)).to eq([node, entry])
    end

    it 'keeps an entry with its own title or description as the article node', :aggregate_failures do
      author = { name: 'N', url: '/authors/n' }

      expect(described_class.article_sources({ title: 'T', author: })).to eq([{ title: 'T', author: }])
      expect(described_class.article_sources({ description: 'D', author: })).to eq([{ description: 'D', author: }])
    end

    it 'ignores bare-name nodes when the entry has its own url', :aggregate_failures do
      content = { title: 'T' }
      entry = { url: '/a', content:, author: { name: 'N', url: '/authors/n' } }

      expect(described_class.article_sources(entry)).to eq([content, entry])
      name_only = { url: '/a', author: { name: 'N' } }

      expect(described_class.article_sources(name_only)).to eq([name_only])
    end

    it 'lists the entry before a node that carries its own url' do
      content = { title: 'T', url: '/node' }
      entry = { url: '/a', content: }

      expect(described_class.article_sources(entry)).to eq([entry, content])
    end

    it 'skips an entry with its own url when article-titled nodes compete', :aggregate_failures do
      entry = { url: '/a', content: { title: 'T' }, related: { headline: 'R', url: '/r' } }

      expect(described_class.article_sources(entry)).to be_nil
    end

    it 'prefers the only nested node with title and url over title-only siblings' do
      node = { title: 'T', url: '/a' }
      entry = { author: { name: 'N' }, node: }

      expect(described_class.article_sources(entry)).to eq([node, entry])
    end

    it 'finds a node two levels down but not three', :aggregate_failures do
      node = { title: 'T', url: '/a' }
      two = { data: { attributes: node } }

      expect(described_class.article_sources(two)).to eq([node, two])
      expect(described_class.article_sources({ a: { b: { c: node } } })).to eq([{ a: { b: { c: node } } }])
    end

    it 'does not search inside a titled node' do
      node = { title: 'T', url: '/a', image: { title: 'Alt', url: '/i.jpg' } }

      expect(described_class.article_sources({ node: })).to eq([node, { node: }])
    end

    it 'falls back to the only titled node when none carries a url' do
      attributes = { title: 'T' }
      entry = { attributes:, links: { self: '/a' } }

      expect(described_class.article_sources(entry)).to eq([attributes, entry])
    end

    it 'returns nil when titled nodes compete without urls' do
      expect(described_class.article_sources({ a: { title: 'A' }, b: { name: 'B' } })).to be_nil
    end

    it 'keeps the bare entry when no nested node has a title' do
      entry = { url: '/a', meta: { url: '/b' } }

      expect(described_class.article_sources(entry)).to eq([entry])
    end
  end

  describe '.linked?' do
    it 'requires title and url values across the sources', :aggregate_failures do
      expect(described_class.linked?([{ title: 'T' }, { url: '/a' }])).to be(true)
      expect(described_class.linked?({ title: '', links: { self: '/a' } })).to be(true)
      expect(described_class.linked?({ title: nil, url: '/a' })).to be(false)
      expect(described_class.linked?({ title: 'T', url: nil })).to be(false)
      expect(described_class.linked?({ title: 'T' })).to be(false)
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

    it 'unwraps array-form links and Hash subclasses', :aggregate_failures do
      links = [{ rel: 'author', title: 'x' }, { rel: 'self', href: '/x' }]

      expect(described_class.unwrap_url(links, described_class::URL_KEYS)).to eq('/x')
      expect(described_class.unwrap_url(Class.new(Hash)[href: '/y'], described_class::URL_KEYS)).to eq('/y')
    end

    it 'returns nil when an array is left after three unwraps' do
      expect(described_class.unwrap_url({ self: { href: { href: ['/x'] } } }, described_class::URL_KEYS)).to be_nil
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

    it 'reads published keys without a date suffix before date-suffixed keys', :aggregate_failures do
      expect(described_class.published_at({ updatedOn: '2020', date: '2026-01-02' })).to eq('2026-01-02')
      expect(described_class.published_at([{ title: 'x' }, { updatedOn: '2020' }, { date: '2026' }])).to eq('2026')
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
    it 'returns nil for input that is neither a hash nor sources', :aggregate_failures do
      expect(described_class.suffix_date_value(nil)).to be_nil
      expect(described_class.suffix_date_value('x')).to be_nil
      expect(described_class.suffix_date_value([])).to be_nil
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

    it 'searches field sources in order', :aggregate_failures do
      expect(described_class.suffix_date_value([{ title: 'x' }, { createdAt: 'a' }, { createdAt: 'd' }])).to eq('a')
      expect(described_class.suffix_date_value({ data: { createdAt: 'd' } })).to be_nil
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
