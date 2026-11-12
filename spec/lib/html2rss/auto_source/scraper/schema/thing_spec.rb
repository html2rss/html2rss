# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::Thing do
  subject(:instance) { described_class.new(schema_object, url: 'https://example.com') }

  let(:schema_object) do
    { '@type': 'ScholarlyArticle', headline: 'Baustellen der Nation' }
  end

  specify { expect(described_class::SUPPORTED_TYPES).to be_a(Set) }

  describe '#call' do
    subject(:call) { instance.call }

    it 'sets the title from headline' do
      expect(call).to include(title: 'Baustellen der Nation')
    end

    context 'when the schema object carries every article field' do
      let(:schema_object) do
        {
          '@type': 'NewsArticle',
          '@id': 'https://example.com/a1',
          headline: 'Head',
          description: 'Desc',
          author: 'Ada',
          url: 'https://example.com/a1',
          image: 'https://example.com/i.jpg',
          datePublished: '2024-01-02',
          articleSection: 'World'
        }
      end

      it 'maps every attribute to its value', :aggregate_failures do
        expect(call).to include(
          id: '/a1', title: 'Head', description: 'Desc', author: 'Ada',
          published_at: '2024-01-02', categories: ['World']
        )
      end

      it 'keeps the absolute url and image', :aggregate_failures do
        expect(call[:url].to_s).to eq('https://example.com/a1')
        expect(call[:image].to_s).to eq('https://example.com/i.jpg')
      end
    end

    context 'when the schema object carries no article fields' do
      let(:schema_object) { { headline: 'Only title' } }

      it 'returns nil for every absent attribute', :aggregate_failures do
        expect(call).to include(id: nil, description: nil, author: nil, url: nil, image: nil, published_at: nil)
        expect(call[:categories]).to eq([])
        expect(call).not_to have_key(:media)
      end
    end

    context 'when the schema object is a media object' do
      let(:schema_object) do
        { '@type': 'https://schema.org/AudioObject', name: 'Episode one', url: '/e/1', contentUrl: '/e/1.mp3' }
      end

      it 'marks the item media and carries its file', :aggregate_failures do
        expect(call).to include(title: 'Episode one', media: true)
        expect(call[:enclosures].map { _1[:url].to_s }).to eq(['https://example.com/e/1.mp3'])
      end
    end
  end

  describe '#title' do
    subject(:title) { instance.title }

    context 'when the headline is a list' do
      let(:schema_object) { { headline: ['', 'First', 'Second'] } }

      it 'uses the first non-empty entry' do
        expect(title).to eq('First')
      end
    end

    context 'when headline is present' do
      let(:schema_object) { { '@type': 'Article', headline: 'From Headline', name: 'From Name', title: 'Legacy' } }

      it { is_expected.to eq('From Headline') }
    end

    context 'when only name is present' do
      let(:schema_object) { { '@type': 'Article', name: 'From Name', alternativeHeadline: 'Alt', title: 'Legacy' } }

      it { is_expected.to eq('From Name') }
    end

    context 'when only alternativeHeadline is present' do
      let(:schema_object) { { '@type': 'Article', alternativeHeadline: 'Alt', title: 'Legacy' } }

      it { is_expected.to eq('Alt') }
    end

    context 'when only legacy title is present' do
      let(:schema_object) { { '@type': 'Article', title: 'Legacy Title' } }

      it { is_expected.to eq('Legacy Title') }
    end
  end

  describe '#published_at' do
    subject(:published_at) { instance.published_at }

    context 'when only dateCreated is present' do
      let(:schema_object) { { dateCreated: '2024-03-01', dateModified: '2024-04-01' } }

      it 'prefers dateCreated over dateModified' do
        expect(published_at).to eq('2024-03-01')
      end
    end

    context 'when only uploadDate is present' do
      let(:schema_object) { { uploadDate: '2024-05-01' } }

      it 'falls back to uploadDate' do
        expect(published_at).to eq('2024-05-01')
      end
    end

    context 'when datePublished is blank' do
      let(:schema_object) { { datePublished: '', dateModified: '2024-04-01' } }

      it 'falls back to the next date' do
        expect(published_at).to eq('2024-04-01')
      end
    end

    context 'when datePublished is present' do
      let(:schema_object) do
        { '@type': 'Article', headline: 'T', datePublished: '2024-01-01', dateModified: '2024-02-01' }
      end

      it { is_expected.to eq('2024-01-01') }
    end

    context 'when only dateModified is present' do
      let(:schema_object) { { '@type': 'Article', headline: 'T', dateModified: '2024-02-01' } }

      it { is_expected.to eq('2024-02-01') }
    end

    context 'when neither date is present' do
      let(:schema_object) { { '@type': 'Article', headline: 'T' } }

      it { is_expected.to be_nil }
    end

    context 'when datePublished is an empty string and no dateModified exists' do
      let(:schema_object) { { '@type': 'Article', headline: 'T', datePublished: '' } }

      it { is_expected.to be_nil }
    end
  end

  describe '#url' do
    subject(:url) { instance.url }

    context 'when url is absolute' do
      let(:schema_object) { { headline: 'T', url: 'https://example.com/a1' } }

      it 'returns the absolute url', :aggregate_failures do
        expect(url.to_s).to eq('https://example.com/a1')
        expect(instance.url).to be(url)
      end
    end

    context 'when url is relative' do
      let(:schema_object) { { headline: 'T', url: '/story/1' } }

      it { expect(url.to_s).to eq('https://example.com/story/1') }
    end

    context 'when no page url is given' do
      subject(:instance) { described_class.new(schema_object, url: nil) }

      let(:schema_object) { { headline: 'T', url: 'https://example.com/a1' } }

      it { expect(url.to_s).to eq('https://example.com/a1') }
    end

    context 'when url is absent' do
      let(:schema_object) { { headline: 'Bare' } }

      before { allow(Html2rss::Log).to receive(:debug) }

      it 'returns nil and logs the missing url once', :aggregate_failures do
        expect(url).to be_nil
        expect(instance.url).to be_nil
        expect(Html2rss::Log).to have_received(:debug)
          .with(a_string_starting_with('Schema#Thing.url: no usable url in schema_object:')).once
      end
    end
  end

  describe '#id' do
    subject(:id) { instance.id }

    context 'when schema object has no @id but has a url' do
      let(:schema_object) { { headline: 'No id', url: 'https://example.com/story/1' } }

      it 'uses the url path as the id' do
        expect(instance.id).to eq('/story/1')
      end
    end

    context 'when @id is an empty string' do
      let(:schema_object) { { '@id': '', url: 'https://example.com/story/2' } }

      it 'falls back to the url path' do
        expect(instance.id).to eq('/story/2')
      end
    end

    context 'when id is requested repeatedly' do
      let(:schema_object) { { '@id': 'https://example.com/memo' } }

      it 'returns the same memoized id on every call' do
        instance.id
        expect(instance.id).to eq('/memo')
      end

      it 'returns the very same object on every call' do
        first = instance.id
        expect(instance.id).to be(first)
      end
    end

    context 'when schema object has neither @id nor url' do
      let(:schema_object) { { headline: 'Bare' } }

      it 'returns nil' do
        expect(instance.id).to be_nil
      end
    end

    context 'when schema_object contains an @id' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', '@id': 'https://example.com/123' }
      end

      it 'normalizes same-origin url ids to their canonical path' do
        expect(id).to eq('/123')
      end
    end

    context 'when schema_object contains a query-permalink @id on the same origin' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', '@id': 'https://example.com/?p=123' }
      end

      it 'preserves the distinguishing query permalink' do
        expect(id).to eq('/?p=123')
      end
    end

    context 'when a same-origin @id is only the root path' do
      let(:schema_object) { { '@id': 'https://example.com/' } }

      it { is_expected.to eq('/') }
    end

    context 'when a same-origin @id has a path and a query' do
      let(:schema_object) { { '@id': 'https://example.com/a?x=1' } }

      it 'drops the query when the path identifies the article' do
        expect(id).to eq('/a')
      end
    end

    context 'when a same-origin @id has only a query' do
      let(:schema_object) { { '@id': 'https://example.com?p=7' } }

      it { is_expected.to eq('/?p=7') }
    end

    context 'when a relative @id contains dot segments' do
      let(:schema_object) { { '@id': '/news/../story/7' } }

      it { is_expected.to eq('/story/7') }
    end

    context 'when the @id is on the article host, which differs from the page host' do
      let(:schema_object) { { '@id': 'https://other.test/p/1', url: 'https://other.test/a' } }

      it { is_expected.to eq('/p/1') }
    end

    context 'when the url is absent and the @id is on the page host' do
      let(:schema_object) { { '@id': 'https://example.com/p' } }

      it { is_expected.to eq('/p') }
    end

    context 'when the @id is on another host and an explicit url is present' do
      let(:schema_object) { { '@id': 'https://other.example.net/post/1', url: 'https://example.com/story' } }

      it 'keeps the original identifier' do
        expect(id).to eq('https://other.example.net/post/1')
      end
    end

    context 'when only an absolute @id is present' do
      let(:schema_object) { { '@id': 'https://other.example.net/post/1' } }

      it 'derives the id from the @id fallback url path' do
        expect(id).to eq('/post/1')
      end
    end

    context 'when schema_object contains a non-url @id' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', '@id': 'article-123' }
      end

      it 'returns the original identifier' do
        expect(id).to eq('article-123')
      end
    end

    context 'when schema_object does not contain an @id or URL' do
      let(:schema_object) { { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' } }

      it 'returns nil' do
        expect(id).to be_nil
      end
    end
  end

  describe '#image' do
    subject(:image) { instance.image }

    {
      'untyped object with url' => [{ image: { url: 'https://example.com/u.jpg' } }, 'https://example.com/u.jpg'],
      'untyped object with contentUrl' => [{ image: { contentUrl: 'https://example.com/c.jpg' } },
                                           'https://example.com/c.jpg'],
      'typed non-ImageObject' => [{ image: { '@type': 'Thing', url: 'https://example.com/no.jpg' } }, nil],
      'thumbnail string' => [{ thumbnail: 'https://example.com/t.jpg' }, 'https://example.com/t.jpg'],
      'thumbnail ImageObject' => [{ thumbnail: { '@type': 'ImageObject', url: 'https://example.com/t.jpg' } },
                                  'https://example.com/t.jpg'],
      'image wins over thumbnail' => [{ image: 'https://example.com/i.jpg', thumbnail: 'https://example.com/t.jpg' },
                                      'https://example.com/i.jpg']
    }.each do |name, (object, expected)|
      context "with #{name}" do
        let(:schema_object) { object }

        it { expect(image&.to_s).to eq(expected) }
      end
    end

    context 'when image is an array of urls' do
      let(:schema_object) { { image: ['https://example.com/a.jpg', 'https://example.com/b.jpg'] } }

      it 'uses the first entry' do
        expect(image.to_s).to eq('https://example.com/a.jpg')
      end
    end

    context 'when image is an array mixing unusable entries and an ImageObject' do
      let(:schema_object) do
        { image: [{ '@type': 'Thing', url: 'https://example.com/no.jpg' },
                  { '@type': 'ImageObject', url: 'https://example.com/yes.jpg' }] }
      end

      it 'skips unusable entries' do
        expect(image.to_s).to eq('https://example.com/yes.jpg')
      end
    end

    context 'when image is an empty array and thumbnailUrl is set' do
      let(:schema_object) { { image: [], thumbnailUrl: 'https://example.com/t.jpg' } }

      it 'falls back to the thumbnail' do
        expect(image.to_s).to eq('https://example.com/t.jpg')
      end
    end

    context 'when image is a non-ImageObject hash' do
      let(:schema_object) { { image: { '@type': 'Thing', url: 'https://example.com/not-image.jpg' } } }

      it 'ignores it' do
        expect(instance.image).to be_nil
      end
    end

    context 'when image is an ImageObject without url or contentUrl' do
      let(:schema_object) { { image: { '@type': 'ImageObject', caption: 'Cap' } } }

      it 'returns nil' do
        expect(instance.image).to be_nil
      end
    end

    context 'when image is an object without any @type' do
      let(:schema_object) { { image: { url: 'https://example.com/i.jpg' } } }

      it { expect(image.to_s).to eq('https://example.com/i.jpg') }
    end

    context 'when image is neither a string nor an object' do
      let(:schema_object) { { image: 42 } }

      it { is_expected.to be_nil }
    end

    context 'when image is relative and the base url is present' do
      let(:schema_object) { { image: '/relative.jpg' } }

      it 'resolves it against the base url' do
        expect(instance.image.to_s).to eq('https://example.com/relative.jpg')
      end
    end

    context 'when image is absolute and no page url is given' do
      subject(:instance) { described_class.new(schema_object, url: nil) }

      let(:schema_object) { { image: 'https://cdn.example.org/i.jpg' } }

      it { expect(image.to_s).to eq('https://cdn.example.org/i.jpg') }
    end

    context 'when image is a string' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: '/image.jpg' }
      end

      it 'returns the absolute image URL' do
        expect(image.to_s).to eq('https://example.com/image.jpg')
      end

      it 'returns the same object on repeated calls' do
        first = instance.image
        expect(instance.image).to be(first)
      end
    end

    context 'when image is an ImageObject' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: { '@type': 'ImageObject', url: 'http://example.com/image.jpg' } }
      end

      it 'returns the image URL from the ImageObject' do
        expect(image.to_s).to eq('http://example.com/image.jpg')
      end
    end

    context 'when image is an ImageObject with contentUrl' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: { '@type': 'ImageObject', contentUrl: 'http://example.com/image.jpg' } }
      end

      it 'returns the contentUrl from the ImageObject' do
        expect(image.to_s).to eq('http://example.com/image.jpg')
      end
    end

    context 'when image is a String' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: 'http://example.com/image1.jpg' }
      end

      it 'returns the first image URL' do
        expect(image.to_s).to eq('http://example.com/image1.jpg')
      end
    end

    context 'when thumbnailUrl is a String' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', thumbnailUrl: 'http://example.com/image1.jpg' }
      end

      it 'returns the first image URL' do
        expect(image.to_s).to eq('http://example.com/image1.jpg')
      end
    end

    context 'when image is nil' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: nil }
      end

      it 'returns nil' do
        expect(image).to be_nil
      end
    end
  end

  describe '#categories' do
    subject(:categories) { instance.categories }

    context 'when schema_object has articleSection' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', headline: 'Baustellen der Nation', articleSection: 'Politics' }
      end

      it 'includes articleSection as a category' do
        expect(categories).to eq(%w[Politics])
      end
    end

    context 'when schema_object has keywords as array' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: %w[Politics Society Analysis] }
      end

      it 'returns the keywords as categories' do
        expect(categories).to eq(%w[Politics Society Analysis])
      end
    end

    context 'when schema_object has keywords as string' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: 'Politics, Society, Analysis' }
      end

      it 'splits keywords by comma and returns as categories' do
        expect(categories).to eq(%w[Politics Society Analysis])
      end
    end

    context 'when schema_object has categories field' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', categories: %w[News Technology] }
      end

      it 'returns the categories' do
        expect(categories).to eq(%w[News Technology])
      end
    end

    context 'when schema_object has tags field' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', tags: %w[Science Research] }
      end

      it 'returns the tags as categories' do
        expect(categories).to eq(%w[Science Research])
      end
    end

    context 'when schema_object has about field with objects' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation',
          about: [{ name: 'Politics' }, { name: 'Society' }] }
      end

      it 'extracts names from about objects' do
        expect(categories).to eq(%w[Politics Society])
      end
    end

    context 'when schema_object has mixed category sources' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: ['Politics'], categories: ['Society'],
          tags: 'Science, Research' }
      end

      it 'combines all category sources' do
        expect(categories).to eq(%w[Politics Society Science Research])
      end
    end

    context 'when schema_object has no category fields' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' }
      end

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end

    context 'when schema_object has empty category fields' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: [], categories: '', tags: nil }
      end

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end
  end

  describe '#description' do
    subject(:description) { instance.description }

    context 'when the description is a list' do
      let(:schema_object) { { description: ['', 'Listed summary'] } }

      it 'uses the first non-empty entry' do
        expect(description).to eq('Listed summary')
      end
    end

    context 'when only abstract is present' do
      let(:schema_object) { { abstract: 'Abstract text' } }

      it { expect(description).to eq('Abstract text') }
    end

    context 'when only schema_object_body is present' do
      let(:schema_object) { { schema_object_body: 'Body text' } }

      it { expect(description).to eq('Body text') }
    end

    context 'when description is the longest candidate' do
      let(:schema_object) { { description: 'A much longer description', articleBody: 'short' } }

      it { expect(description).to eq('A much longer description') }
    end

    context 'when no description-like field exists' do
      let(:schema_object) { { headline: 'Nothing else' } }

      it { expect(description).to be_nil }
    end

    context 'when articleBody is longer than description' do
      let(:schema_object) do
        { '@type': 'Article', title: 'Test', description: 'Short', articleBody: 'This is a much longer article body' }
      end

      it 'selects articleBody' do
        expect(description).to eq('This is a much longer article body')
      end
    end
  end

  describe '#author' do
    subject(:author) { instance.author }

    context 'when author is an empty array' do
      let(:schema_object) { { author: [], publisher: 'Pub Co' } }

      it 'falls back to the publisher' do
        expect(instance.author).to eq('Pub Co')
      end
    end

    context 'when author is an array mixing names, persons and unusable entries' do
      let(:schema_object) { { author: ['Ada', { name: 'Bob' }, 42, nil] } }

      it 'joins only the usable names' do
        expect(instance.author).to eq('Ada, Bob')
      end
    end

    context 'when author is whitespace-only' do
      let(:schema_object) { { author: "  \n ", publisher: 'Pub Co' } }

      it 'falls back to the publisher' do
        expect(instance.author).to eq('Pub Co')
      end
    end

    context 'when author is a Person hash without a name' do
      let(:schema_object) { { author: { '@type': 'Person', url: 'https://example.com/p' }, publisher: 'Pub Co' } }

      it 'falls back to the publisher' do
        expect(instance.author).to eq('Pub Co')
      end
    end

    context 'when author is a Person hash with a blank name' do
      let(:schema_object) { { author: { name: '   ' }, publisher: 'Pub Co' } }

      it 'falls back to the publisher' do
        expect(instance.author).to eq('Pub Co')
      end
    end

    context 'when author is a Person hash with a non-string name' do
      let(:schema_object) { { author: { name: 42 } } }

      it { is_expected.to eq('42') }
    end

    context 'when author is a Person hash with surrounding whitespace in name' do
      let(:schema_object) { { author: { name: '  Ada Lovelace  ' } } }

      it 'returns the stripped name' do
        expect(instance.author).to eq('Ada Lovelace')
      end
    end

    context 'when author is a string' do
      let(:schema_object) { { '@type': 'Article', title: 'Test', author: ' Jane Doe ' } }

      it { is_expected.to eq('Jane Doe') }
    end

    context 'when author is a Person hash with name' do
      let(:schema_object) { { '@type': 'Article', title: 'Test', author: { '@type': 'Person', name: 'John Doe' } } }

      it { is_expected.to eq('John Doe') }
    end

    context 'when author is an array of persons/strings' do
      let(:schema_object) do
        { '@type': 'Article', title: 'Test', author: ['Alice', { '@type': 'Person', name: 'Bob' }] }
      end

      it { is_expected.to eq('Alice, Bob') }
    end

    context 'when author is absent but publisher is present' do
      let(:schema_object) do
        { '@type': 'Article', title: 'Test', publisher: { '@type': 'Organization', name: 'Acme News' } }
      end

      it { is_expected.to eq('Acme News') }
    end

    context 'when both author and publisher are absent' do
      let(:schema_object) { { '@type': 'Article', title: 'Test' } }

      it { is_expected.to be_nil }
    end
  end

  describe '#url with malformed values' do
    subject(:url) { instance.url }

    context 'when the url is a list' do
      let(:schema_object) { { url: ['https://example.com/a'] } }

      it 'uses the first entry' do
        expect(url.to_s).to eq('https://example.com/a')
      end
    end

    context 'when the url is not a string' do
      let(:schema_object) { { url: { '@id': 'https://example.com/a' } } }

      it 'returns nil instead of raising' do
        expect(url).to be_nil
      end
    end

    context 'when the url cannot be parsed' do
      let(:schema_object) { { url: 'http://' } }

      it 'returns nil instead of raising' do
        expect(url).to be_nil
      end
    end

    {
      'mainEntityOfPage string' => [{ mainEntityOfPage: 'https://example.com/m#top' }, 'https://example.com/m'],
      'mainEntityOfPage @id' => [{ mainEntityOfPage: { '@id': 'https://example.com/m' } }, 'https://example.com/m'],
      'mainEntityOfPage url' => [{ mainEntityOfPage: { url: 'https://example.com/m' } }, 'https://example.com/m'],
      'absolute @id' => [{ '@id': 'https://example.com/i#article' }, 'https://example.com/i'],
      'mainEntityOfPage over @id' => [{ mainEntityOfPage: 'https://example.com/m', '@id': 'https://example.com/i' },
                                      'https://example.com/m'],
      'explicit url over fallbacks' => [{ url: 'https://example.com/u#frag', mainEntityOfPage: 'https://e.com/m' },
                                        'https://example.com/u#frag'],
      'non-http mainEntityOfPage' => [{ mainEntityOfPage: 'urn:uuid:1', '@id': 'ftp://example.com/x' }, nil],
      'embedUrl never' => [{ embedUrl: 'https://example.com/embed/1#t' }, nil],
      '@id over embedUrl' => [{ '@id': 'https://example.com/i', embedUrl: 'https://example.com/embed/1' },
                              'https://example.com/i'],
      'page url over embedUrl' => [{ url: 'https://example.com/v/1', embedUrl: 'https://example.com/embed/1' },
                                   'https://example.com/v/1'],
      'contentUrl never' => [{ contentUrl: 'https://example.com/v.mp4' }, nil],
      'relative @id' => [{ '@id': '/relative' }, nil]
    }.each do |name, (object, expected)|
      context "when falling back with #{name}" do
        let(:schema_object) { object }

        it 'resolves the expected url' do
          expect(url&.to_s).to eq(expected)
        end
      end
    end
  end

  describe '#enclosures' do
    subject(:enclosures) do
      instance.call[:enclosures]&.map { |enc| enc.except(:url).compact.merge(url: enc[:url].to_s) }
    end

    {
      'video with encodingFormat' => [{ video: { '@type': 'VideoObject', contentUrl: 'https://example.com/v.mp4',
                                                 encodingFormat: 'video/mp4' } },
                                      [{ url: 'https://example.com/v.mp4', type: 'video/mp4', kind: :video }]],
      'audio without encodingFormat' => [{ audio: { '@type': 'AudioObject', contentUrl: '/a.mp3' } },
                                         [{ url: 'https://example.com/a.mp3', kind: :audio }]],
      'video and audio lists' => [{ video: [{ contentUrl: 'https://example.com/1.mp4' }],
                                    audio: [{ contentUrl: 'https://example.com/2.mp3' }, 'junk'] },
                                  [{ url: 'https://example.com/1.mp4' }, { url: 'https://example.com/2.mp3' }]],
      'embedUrl only' => [{ video: { embedUrl: 'https://example.com/embed' } }, nil],
      'no media' => [{}, nil],
      'associatedMedia with size and duration' => [
        { associatedMedia: { '@type': 'MediaObject', contentUrl: '/e.mp3', encodingFormat: 'audio/mpeg',
                             contentSize: '12.3 MB', duration: 'PT1M5S' } },
        [{ url: 'https://example.com/e.mp3', type: 'audio/mpeg', bytes_length: 12_300_000, duration: 65 }]
      ],
      'associatedMedia list with an image' => [
        { associatedMedia: [{ '@type': 'ImageObject', contentUrl: '/p.jpg' }, { contentUrl: '/r.pdf' }] },
        [{ url: 'https://example.com/r.pdf' }]
      ],
      'video before audio before associatedMedia' => [
        { associatedMedia: { contentUrl: '/3.mp3' }, audio: { contentUrl: '/2.mp3' }, video: { contentUrl: '/1.mp4' } },
        [{ url: 'https://example.com/1.mp4' }, { url: 'https://example.com/2.mp3' },
         { url: 'https://example.com/3.mp3' }]
      ],
      'a media format name' => [{ audio: { contentUrl: '/a', encodingFormat: 'MP3' } },
                                [{ url: 'https://example.com/a', type: 'audio/mpeg' }]],
      'a dotted media format name' => [{ video: { contentUrl: '/v', encodingFormat: ' .webm ' } },
                                       [{ url: 'https://example.com/v', type: 'video/webm' }]],
      'an unknown format name' => [{ audio: { contentUrl: '/a.mp3', encodingFormat: 'stereo' } },
                                   [{ url: 'https://example.com/a.mp3' }]],
      'a MIME type with parameters' => [{ audio: { contentUrl: '/a.mp3', encodingFormat: 'Audio/MPEG; rate=44100' } },
                                        [{ url: 'https://example.com/a.mp3', type: 'audio/mpeg' }]],
      'a non-String encodingFormat' => [{ audio: { contentUrl: '/a.mp3', encodingFormat: ['audio/mpeg'] } },
                                        [{ url: 'https://example.com/a.mp3' }]],
      'a contentUrl list' => [{ video: { contentUrl: ['', 'https://example.com/v.mp4'] } },
                              [{ url: 'https://example.com/v.mp4' }]],
      'a duration on the episode' => [
        { '@type': 'PodcastEpisode', duration: 'PT2M', associatedMedia: { contentUrl: '/e.mp3', duration: 'bad' } },
        [{ url: 'https://example.com/e.mp3', duration: 120 }]
      ],
      'the media object itself' => [{ '@type': 'AudioObject', contentUrl: '/self.mp3', contentSize: '1 KiB',
                                      duration: 'PT1H' },
                                    [{ url: 'https://example.com/self.mp3', bytes_length: 1024, duration: 3600,
                                       kind: :audio }]],
      'a media object among types' => [{ '@type': %w[CreativeWork Clip], contentUrl: '/c' },
                                       [{ url: 'https://example.com/c', kind: :video }]],
      'a javascript contentUrl' => [{ video: { contentUrl: 'javascript:void(0)' } }, nil],
      'a blob contentUrl' => [{ video: { contentUrl: 'blob:https://example.com/x' } }, nil],
      'an unusable contentUrl' => [{ video: { contentUrl: 'http://' } }, nil],
      'an empty contentUrl' => [{ video: { contentUrl: '' } }, nil],
      'a non-String contentUrl' => [{ video: { contentUrl: 42 } }, nil],
      'a contentUrl on an article' => [{ '@type': 'NewsArticle', contentUrl: '/a.pdf' }, nil]
    }.each do |name, (extra, expected)|
      context "with #{name}" do
        let(:schema_object) { extra }

        it { is_expected.to eq(expected) }
      end
    end

    {
      'AudioObject' => 'audio/mpeg', 'PodcastEpisode' => 'audio/mpeg',
      'VideoObject' => 'video/mp4', 'Clip' => 'video/mp4'
    }.each do |type, mime|
      context "with an untyped #{type} file without a media extension" do
        let(:schema_object) { { '@type': type, url: 'https://example.com/ep/1', contentUrl: '/files/ep1' } }

        it "ships it as #{mime}" do
          expect(instance.call[:enclosures].map { Html2rss::Article::Enclosure.new(**_1).type }).to eq([mime])
        end
      end
    end

    context 'with a PodcastEpisode whose file names its own type' do
      let(:schema_object) { { '@type': 'PodcastEpisode', url: 'https://example.com/ep/1', contentUrl: '/ep1.mp4' } }

      it 'keeps the file type' do
        expect(instance.call[:enclosures].map { Html2rss::Article::Enclosure.new(**_1).type }).to eq(['video/mp4'])
      end
    end

    context 'with a PodcastEpisode duration beside a transcript' do
      let(:schema_object) do
        { '@type': 'PodcastEpisode', url: 'https://example.com/ep/1', duration: 'PT30M',
          associatedMedia: [{ '@type': 'MediaObject', contentUrl: '/ep1.mp3' },
                            { '@type': 'MediaObject', contentUrl: '/ep1-transcript.pdf' }] }
      end

      it 'times only the audio file' do
        files = Html2rss::Article.new(**instance.call).enclosures

        expect(files.map { [_1.url.to_s, _1.duration] })
          .to eq([['https://example.com/ep1.mp3', 1800], ['https://example.com/ep1-transcript.pdf', nil]])
      end
    end

    context 'without a page url' do
      subject(:instance) { described_class.new(schema_object, url: nil) }

      let(:schema_object) { { audio: [{ contentUrl: '/relative.mp3' }, { contentUrl: 'https://example.com/a.mp3' }] } }

      it 'keeps only absolute files' do
        expect(enclosures).to eq([{ url: 'https://example.com/a.mp3' }])
      end
    end
  end
end
