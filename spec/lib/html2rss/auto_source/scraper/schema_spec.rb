# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema do
  let(:article_schema_object) do
    # Legacy `title` (non-schema.org) kept so older pages still extract
    {
      '@context': 'https://schema.org',
      '@id': '4582066',
      '@type': 'Article',
      additionalType: 'ArticleTeaser',
      url: '/news/Stadtbibliothek-verlaengert-Oeffnungszeiten-in-Muenchen-9703029.html',
      title: 'Für Pendler öffnet die Stadtbibliothek länger',
      kicker: 'Neue Abendzeiten in München',
      abstract: 'Die Bibliothek bleibt werktags bis 22 Uhr geöffnet.',
      image: 'https://www.example.com/imgs/18/4/5/8/2/0/6/6/library_1777981682-958a1d575a8f5e3e.jpeg'
    }
  end
  let(:news_article_schema_object) do
    # src: https://schema.org/NewsArticle (headline is the official property)
    {
      '@context': 'https://schema.org',
      '@type': 'NewsArticle',
      url: 'http://www.example.com/news/harbor-council-39324587',
      publisher: {
        '@type': 'Organization',
        name: 'Example News',
        logo: 'http://www.example.net/news/special/2015/newsspec_10857/example_news_logo.png?cb=1'
      },
      headline: "Harbor claims: Council's chair confirms review of the 'ferry contract'",
      mainEntityOfPage: 'http://www.example.com/news/harbor-council-39324587',
      articleBody: "The chair says the review of last year's ferry tender will assess if rules were broken.",
      image: [
        'http://img-1.example.net/news/560/media/images/75306000/jpg/_75306515_line976.jpg',
        'http://img.example.net/news/560/cpsprodpb/8AB9/production/_95231553_harbor2.jpg',
        'http://img.example.net/news/560/cpsprodpb/17519/production/_95231559_council.jpg'
      ],
      datePublished: '2017-03-20T20:30:54+00:00'
    }
  end
  let(:simple_article) { ->(type: 'Article', title: 'Sample Title') { { '@type': type, title:, url: 'https://example.com' } } }
  let(:script_tag) { ->(json_content) { Nokogiri::HTML("<script type=\"application/ld+json\">#{json_content}</script>") } }

  before do
    allow(Html2rss::Log).to receive(:warn)
    allow(Html2rss::Log).to receive(:debug)
  end

  describe '.request_slots' do
    it 'reserves no request slots', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_requests: 3)).to eq(0)
    end
  end

  describe '.canonicalize_type' do
    it 'ignores values that are neither strings nor symbols', :aggregate_failures do
      expect(described_class.canonicalize_type(42)).to be_nil
      expect(described_class.canonicalize_type(nil)).to be_nil
    end

    it 'canonicalizes schema.org URLs and case-folded names', :aggregate_failures do
      expect(described_class.canonicalize_type('https://schema.org/newsarticle')).to eq('NewsArticle')
      expect(described_class.canonicalize_type(:NewsArticle)).to eq('NewsArticle')
    end

    it 'returns nil for an empty type name after stripping the schema.org prefix' do
      expect(described_class.canonicalize_type('https://schema.org/')).to be_nil
    end
  end

  describe '#extractable?' do
    subject(:extractable?) { described_class.new(parsed_body, url: '').extractable? }

    context 'when a JSON-LD script holds a supported article' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"NewsArticle","headline":"x"}</script>')
      end

      it { expect(extractable?).to be true }
    end

    context 'when only unsupported JSON-LD is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"Organization","name":"x"}</script>')
      end

      it { expect(extractable?).to be false }
    end

    context 'when a supported article sits in a non JSON-LD script' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/json">{"@type":"NewsArticle","headline":"x"}</script>')
      end

      it { expect(extractable?).to be false }
    end
  end

  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:schema) }
  end

  describe '.articles?(parsed_body)' do
    subject(:articles?) { described_class.articles?(parsed_body) }

    context 'with an unsupported JSON-LD script followed by a supported one' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <script type="application/ld+json">{"@type":"Organization","name":"x"}</script>
          <script type="application/ld+json">{"@type":"Article","headline":"y"}</script>
        HTML
      end

      it { expect(articles?).to be true }
    end

    context 'with only unsupported JSON-LD scripts' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"Organization","name":"x"}</script>')
      end

      it { expect(articles?).to be false }
    end

    context 'with a NewsArticle' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{news_article_schema_object.to_json}</script>")
      end

      it { is_expected.to be_truthy }
    end

    context 'with an Article' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{article_schema_object.to_json}</script>")
      end

      it { is_expected.to be_truthy }
    end

    context 'with a standalone PodcastEpisode' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type": "PodcastEpisode", "name": "E"}</script>')
      end

      it { is_expected.to be(true) }
    end

    context 'with uppercase JSON-LD MIME type' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"APPLICATION/LD+JSON\">#{news_article_schema_object.to_json}</script>")
      end

      it { is_expected.to be_truthy }
    end

    context 'with an empty body' do
      let(:parsed_body) { Nokogiri::HTML.fragment('') }

      it { is_expected.to be_falsey }
    end

    context 'with excessive spacing in JSON and supported @type' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type"  :  "NewsArticle"  }</script>')
      end

      it { is_expected.to be_truthy }
    end

    context 'with schema.org URL @type' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"https://schema.org/NewsArticle"}</script>')
      end

      it { is_expected.to be_truthy }
    end

    context 'with multi-type @type array' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":["Article","NewsArticle"]}</script>')
      end

      it { is_expected.to be_truthy }
    end

    context 'with multi-type @type array where supported type is not first' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":["WebPage","NewsArticle"]}</script>')
      end

      it { is_expected.to be_truthy }
    end

    context 'with lowercase @type' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"newsarticle"}</script>')
      end

      it { is_expected.to be_truthy }
    end

    context 'with mixed-case schema.org URL @type' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/ld+json">{"@type":"https://schema.org/NEWSARTICLE"}</script>')
      end

      it { is_expected.to be_truthy }
    end
  end

  describe '.self.from(object)' do
    subject(:array) { described_class.from(object) }

    context 'with nil' do
      let(:object) { nil }

      it 'scrapes the article' do
        expect(array).to eq([])
      end
    end

    context 'with a Article schema object' do
      let(:object) { article_schema_object }

      it 'scrapes the article' do
        expect(array).to include(hash_including('@type': 'Article'))
      end
    end

    context 'with an ItemList schema object' do
      let(:object) do
        {
          '@context': 'https://schema.org',
          '@type': 'ItemList',
          itemListElement: [
            {
              '@type': 'ListItem',
              position: 1,
              url: 'https://www.example.com/breakdancerin-raygun-geht-weiter-110168077.html'
            },
            {
              '@type': 'ListItem',
              position: 2,
              url: 'https://www.example.com/in-frankfurt-macht-die-neue-grundsteuer-das-wohnen-noch-teurer-110165876.html'
            }
          ]
        }
      end

      it 'returns the ItemList for element expansion' do
        expect(array).to include(hash_including('@type': 'ItemList'))
      end
    end

    context 'with a Blog container and blogPost articles' do
      let(:object) do
        {
          '@type': 'Blog',
          name: 'My Blog',
          blogPost: [
            { '@type': 'BlogPosting', headline: 'First Post', url: 'https://example.com/1' },
            { '@type': 'BlogPosting', headline: 'Second Post', url: 'https://example.com/2' }
          ]
        }
      end

      it 'walks blogPost and does not return the Blog container', :aggregate_failures do
        expect(array).to contain_exactly(
          hash_including('@type': 'BlogPosting', headline: 'First Post'),
          hash_including('@type': 'BlogPosting', headline: 'Second Post')
        )
      end
    end

    context 'with a WebPage mainEntity Article' do
      let(:object) do
        {
          '@type': 'WebPage',
          name: 'Page shell',
          mainEntity: {
            '@type': 'Article',
            headline: 'Main Entity Article',
            url: 'https://example.com/main'
          }
        }
      end

      it 'prefers mainEntity and skips the WebPage container' do
        expect(array).to contain_exactly(hash_including('@type': 'Article', headline: 'Main Entity Article'))
      end
    end

    context 'with multi-type NewsArticle and WebPage' do
      let(:object) do
        {
          '@type': %w[NewsArticle WebPage],
          headline: 'Hybrid Article',
          url: 'https://example.com/hybrid'
        }
      end

      it 'returns the article-shaped node despite denied WebPage' do
        expect(array).to contain_exactly(
          hash_including('@type': %w[NewsArticle WebPage], headline: 'Hybrid Article')
        )
      end
    end

    context 'with an @graph of mixed containers and articles' do
      let(:object) do
        {
          '@context': 'https://schema.org',
          '@graph': [
            { '@type': 'BreadcrumbList', itemListElement: [{ '@type': 'ListItem', name: 'Home' }] },
            { '@type': 'NewsArticle', headline: 'Graph Article', url: 'https://example.com/g' }
          ]
        }
      end

      it 'returns only article-shaped nodes from @graph' do
        expect(array).to contain_exactly(hash_including('@type': 'NewsArticle', headline: 'Graph Article'))
      end
    end

    context 'with standalone media objects in @graph and in an array' do
      let(:object) do
        [
          { '@graph': [{ '@type': 'PodcastSeries', name: 'Show' }, { '@type': 'PodcastEpisode', name: 'Episode' }] },
          [{ '@type': 'https://schema.org/VideoObject', name: 'Video' }, { '@type': 'Clip', name: 'Clip' }],
          { '@type': 'AudioObject', name: 'Audio' }
        ]
      end

      it 'returns every media object' do
        expect(array.map { _1[:name] }).to eq(%w[Episode Video Clip Audio])
      end
    end

    context 'with a media object nested in an article' do
      let(:object) do
        { '@type': 'NewsArticle', headline: 'Story', associatedMedia: { '@type': 'VideoObject', name: 'Video' } }
      end

      it 'returns the article only' do
        expect(array).to contain_exactly(hash_including(headline: 'Story'))
      end
    end

    context 'with a deeply nested object' do
      let(:object) do
        {
          foo: [
            {
              bar: { baz: { qux: { quux: { corge: [news_article_schema_object] } } } },
              grault: { garply: { waldo: { fred: { plugh: { xyzzy: [article_schema_object] } } } } }
            }
            # Good to have these documented. *cough*
          ]
        }
      end

      it 'scrapes the NewsArticle and Article stabile', :aggregate_failures do
        first, second = array

        expect(first).to include(:@type => 'NewsArticle')
        expect(second).to include(:@type => 'Article')
      end
    end
  end

  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: '') }

    let(:parsed_body) { Nokogiri::HTML('') }

    context 'with an article whose url is relative to the page url' do
      subject(:new) { described_class.new(parsed_body, url: 'https://example.com/list') }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <script type="application/ld+json">{"@type":"NewsArticle","headline":"Rel","url":"/story/9"}</script>
        HTML
      end

      it 'resolves the article url against the page url' do
        expect(new.first[:url].to_s).to eq('https://example.com/story/9')
      end
    end

    context 'with a supported article in a non JSON-LD script' do
      let(:parsed_body) do
        Nokogiri::HTML('<script type="application/json">{"@type":"NewsArticle","headline":"Hidden"}</script>')
      end

      it 'does not emit it' do
        expect(new.to_a).to eq([])
      end
    end

    context 'without a block' do
      it 'returns an enumerator' do
        expect(new.each).to be_a(Enumerator)
      end
    end

    context 'with a NewsArticle' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{news_article_schema_object.to_json}</script>")
      end

      it 'scrapes the article_hash' do
        expect { |b| new.each(&b) }.to yield_with_args(
          hash_including(
            title: "Harbor claims: Council's chair confirms review of the 'ferry contract'"
          )
        )
      end
    end

    context 'with an Article' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{article_schema_object.to_json}</script>")
      end

      it 'scrapes the article' do
        expect do |b|
          new.each(&b)
        end.to yield_with_args hash_including(title: 'Für Pendler öffnet die Stadtbibliothek länger')
      end
    end

    context 'with an empty body' do
      it 'returns an empty array' do
        expect { |b| new.each(&b) }.not_to yield_with_args
      end
    end

    context 'with an unsupported @type' do
      let(:parsed_body) { Nokogiri::HTML('<script type="application/ld+json">{"@type": "foo"}</script>') }

      it 'returns an empty array' do
        expect { |b| new.each(&b) }.not_to yield_with_args
      end
    end

    context 'with malformed JSON' do
      let(:parsed_body) { script_tag.call('{invalid json}') }

      it 'logs a warning and returns an empty array', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- structured warn payload
        expect { |b| new.each(&b) }.not_to yield_with_args
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          event = JSON.parse(payload)
          expect(event['event_name']).to eq('schema.parse_failed')
          expect(event['message']).to include("#{described_class}: failed to parse JSON")
        end
      end
    end

    context 'with standalone media objects in @graph' do
      let(:parsed_body) do
        script_tag.call({ '@graph': [
          { '@type': 'PodcastEpisode', name: 'Episode one', url: 'https://example.com/e/1',
            associatedMedia: { '@type': 'MediaObject', contentUrl: 'https://example.com/e1.mp3' } },
          { '@type': 'VideoObject', name: 'Player only', url: 'https://example.com/v/1',
            embedUrl: 'https://example.com/embed/1' }
        ] }.to_json)
      end

      it 'yields each as a media item' do
        expect(new.map { _1.values_at(:title, :media) }).to eq([['Episode one', true], ['Player only', true]])
      end

      it 'takes the file from associatedMedia and none from a player', :aggregate_failures do
        episode, video = new.to_a
        expect(episode[:enclosures].map { _1[:url].to_s }).to eq(['https://example.com/e1.mp3'])
        expect(video).to include(enclosures: nil)
        expect(video[:url].to_s).to eq('https://example.com/v/1')
      end
    end

    context 'with an ItemList that returns an array' do
      let(:parsed_body) { script_tag.call('{"@type": "ItemList", "itemListElement": []}') }

      before do
        item_list_instance = instance_double(Html2rss::AutoSource::Scraper::Schema::ItemList)
        allow(Html2rss::AutoSource::Scraper::Schema::ItemList).to receive(:new).and_return(item_list_instance)
        allow(item_list_instance).to receive(:call).and_return([
                                                                 { title: 'Item 1' },
                                                                 { title: 'Item 2' }
                                                               ])
      end

      it 'yields each item in the array' do
        expect { |b| new.each(&b) }.to yield_successive_args(
          { title: 'Item 1' },
          { title: 'Item 2' }
        )
      end
    end

    context 'with a Blog JSON-LD that must not emit the container' do
      let(:parsed_body) do
        script_tag.call({
          '@type': 'Blog',
          name: 'Container Blog',
          blogPost: {
            '@type': 'BlogPosting',
            headline: 'Only Post',
            url: 'https://example.com/only'
          }
        }.to_json)
      end

      it 'yields blog posts only' do
        expect { |b| new.each(&b) }.to yield_with_args(hash_including(title: 'Only Post'))
      end
    end

    context 'with multi-type NewsArticle and WebPage' do
      let(:parsed_body) do
        script_tag.call({
          '@type': %w[NewsArticle WebPage],
          headline: 'Hybrid via each',
          url: 'https://example.com/hybrid-each'
        }.to_json)
      end

      it 'yields the article despite denied WebPage' do
        expect { |b| new.each(&b) }.to yield_with_args(hash_including(title: 'Hybrid via each'))
      end
    end

    context 'with a scraper that returns nil' do
      let(:parsed_body) { script_tag.call('{"@type": "Article"}') }

      before do
        thing_instance = instance_double(Html2rss::AutoSource::Scraper::Schema::Thing)
        allow(Html2rss::AutoSource::Scraper::Schema::Thing).to receive(:new).and_return(thing_instance)
        allow(thing_instance).to receive(:call).and_return(nil)
      end

      it 'does not yield anything' do
        expect { |b| new.each(&b) }.not_to yield_with_args
      end
    end
  end

  describe '.supported_schema_object?' do
    context 'with a supported schema object' do
      let(:object) { simple_article.call }

      it 'returns true' do
        expect(described_class.supported_schema_object?(object)).to be true
      end
    end

    context 'with an unsupported schema object' do
      let(:object) { simple_article.call(type: 'UnsupportedType') }

      it 'returns false' do
        expect(described_class.supported_schema_object?(object)).to be false
      end
    end
  end

  describe '.scraper_for_schema_object' do
    context 'with a Thing type' do
      let(:object) { simple_article.call }

      it 'returns Thing class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with a lowercase Thing type' do
      let(:object) { simple_article.call(type: 'article') }

      it 'returns Thing class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with an ItemList type' do
      let(:object) { simple_article.call(type: 'ItemList') }

      it 'returns ItemList class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::ItemList)
      end
    end

    context 'with a schema.org URL @type' do
      let(:object) { { '@type': 'https://schema.org/Article', url: 'https://example.com' } }

      it 'returns Thing class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with a multi-type @type array' do
      let(:object) { { '@type': %w[Article NewsArticle], url: 'https://example.com' } }

      it 'returns Thing class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with multi-type including a denied container' do
      let(:object) { { '@type': %w[NewsArticle WebPage], url: 'https://example.com' } }

      it 'prefers Thing over denied container' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with an unsupported type' do
      let(:object) { simple_article.call(type: 'UnsupportedType') }

      it 'logs debug message and returns nil', :aggregate_failures do
        expect(described_class.scraper_for_schema_object(object)).to be_nil
        expect(Html2rss::Log).to have_received(:debug)
          .with("#{described_class}: unsupported schema object @type=\"UnsupportedType\"")
      end
    end
  end

  describe '.normalize_types' do
    it 'strips schema.org URL prefixes', :aggregate_failures do
      expect(described_class.normalize_types('https://schema.org/NewsArticle')).to eq(Set['NewsArticle'])
      expect(described_class.normalize_types('http://schema.org/Article')).to eq(Set['Article'])
    end

    it 'flattens array @type values' do
      expect(described_class.normalize_types(['https://schema.org/Article', 'NewsArticle']))
        .to eq(Set['Article', 'NewsArticle'])
    end

    it 'canonicalizes case-insensitive wire forms to PascalCase', :aggregate_failures do
      expect(described_class.normalize_types('newsarticle')).to eq(Set['NewsArticle'])
      expect(described_class.normalize_types('NEWSARTICLE')).to eq(Set['NewsArticle'])
      expect(described_class.normalize_types('https://schema.org/article')).to eq(Set['Article'])
    end
  end

  describe '.from' do
    context 'with a Nokogiri::XML::Element' do
      let(:script_element) { script_tag.call('{"@type": "Article"}').at_css('script') }

      it 'parses the script tag and returns schema objects' do
        expect(described_class.from(script_element)).to include(hash_including('@type': 'Article'))
      end
    end

    context 'with an array of objects' do
      let(:objects) { [article_schema_object, news_article_schema_object] }

      it 'returns flattened array of schema objects', :aggregate_failures do
        result = described_class.from(objects)
        expect(result).to include(hash_including('@type': 'Article'))
        expect(result).to include(hash_including('@type': 'NewsArticle'))
      end
    end

    context 'with a hash containing unsupported objects' do
      let(:object) { { '@type': 'UnsupportedType', data: 'test' } }

      it 'returns empty array' do
        expect(described_class.from(object)).to eq([])
      end
    end

    context 'with a hash containing nested supported objects' do
      let(:object) { { 'nested' => { 'article' => article_schema_object } } }

      it 'recursively finds and returns supported objects' do
        expect(described_class.from(object)).to include(hash_including('@type': 'Article'))
      end
    end
  end
end
