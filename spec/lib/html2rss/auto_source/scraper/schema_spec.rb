# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema do
  # Test factories for maintainability
  def build_script_tag(json_content)
    Nokogiri::HTML("<script type=\"application/ld+json\">#{json_content}</script>")
  end

  def mock_logging
    allow(Html2rss::Log).to receive(:warn)
    allow(Html2rss::Log).to receive(:debug)
  end

  def build_simple_article(type: 'Article', title: 'Sample Title')
    { '@type': type, title:, url: 'https://example.com' }
  end

  let(:news_article_schema_object) do
    # src: https://schema.org/NewsArticle
    {
      '@context': 'https://schema.org',
      '@type': 'NewsArticle',
      url: 'http://www.bbc.com/news/world-us-canada-39324587',
      publisher: {
        '@type': 'Organization',
        name: 'BBC News',
        logo: 'http://www.bbc.co.uk/news/special/2015/newsspec_10857/bbc_news_logo.png?cb=1'
      },
      title: "Trump Russia claims: FBI's Comey confirms investigation of election 'interference'",
      mainEntityOfPage: 'http://www.bbc.com/news/world-us-canada-39324587',
      articleBody: "Director Comey says the probe into last year's US election would assess if crimes were committed.",
      image: [
        'http://ichef-1.bbci.co.uk/news/560/media/images/75306000/jpg/_75306515_line976.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/8AB9/production/_95231553_comey2.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/17519/production/_95231559_committee.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/CC81/production/_95235325_f704a6dc-c017-4971-aac3-04c03eb097fb.jpg',
        'http://ichef-1.bbci.co.uk/news/560/cpsprodpb/11AA1/production/_95235327_c0b59f9e-316e-4641-aa7e-3fec6daea62b.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/0F99/production/_95239930_trumptweet.png',
        'http://ichef-1.bbci.co.uk/news/560/cpsprodpb/10DFA/production/_95241196_mediaitem95241195.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/2CA0/production/_95242411_comey.jpg',
        'http://ichef.bbci.co.uk/news/560/cpsprodpb/11318/production/_95242407_mediaitem95242406.jpg',
        'http://ichef-1.bbci.co.uk/news/560/cpsprodpb/BCED/production/_92856384_line976.jpg',
        'http://ichef-1.bbci.co.uk/news/560/cpsprodpb/12B64/production/_95244667_mediaitem95244666.jpg'
      ],
      datePublished: '2017-03-20T20:30:54+00:00'
    }
  end

  let(:article_schema_object) do
    {
      '@context': 'https://schema.org',
      '@id': '4582066',
      '@type': 'Article',
      additionalType: 'ArticleTeaser',
      url: '/news/Google-entlaesst-Python-Team-fuer-billigere-Arbeitskraefte-in-Muenchen-9703029.html',
      title: 'Für Einsparungen kündigt Google komplettem Python-Team',
      kicker: 'Ersatz wohl in München',
      abstract: 'Einem Python-Team wurde offenbar komplett gekündigt.',
      image: 'https://www.heise.de/imgs/18/4/5/8/2/0/6/6/shutterstock_1777981682-958a1d575a8f5e3e.jpeg'
    }
  end

  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:schema) }
  end

  describe '.articles?(parsed_body)' do
    subject(:articles?) { described_class.articles?(parsed_body) }

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

      it 'returns the ItemList' do
        expect(array).to include(hash_including('@type': 'ItemList'))
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
            title: "Trump Russia claims: FBI's Comey confirms investigation of election 'interference'"
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
        end.to yield_with_args hash_including(title: 'Für Einsparungen kündigt Google komplettem Python-Team')
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
      let(:parsed_body) { build_script_tag('{invalid json}') }

      before { mock_logging }

      it 'logs a warning and returns an empty array', :aggregate_failures do
        expect { |b| new.each(&b) }.not_to yield_with_args
        expect(Html2rss::Log).to have_received(:warn).with(/Failed to parse JSON/, error: anything)
      end
    end

    context 'with an ItemList that returns an array' do
      let(:parsed_body) { build_script_tag('{"@type": "ItemList", "itemListElement": []}') }

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

    context 'with a scraper that returns nil' do
      let(:parsed_body) { build_script_tag('{"@type": "Article"}') }

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
      let(:object) { build_simple_article }

      it 'returns true' do
        expect(described_class.supported_schema_object?(object)).to be true
      end
    end

    context 'with an unsupported schema object' do
      let(:object) { build_simple_article(type: 'UnsupportedType') }

      it 'returns false' do
        expect(described_class.supported_schema_object?(object)).to be false
      end
    end
  end

  describe '.scraper_for_schema_object' do
    context 'with a Thing type' do
      let(:object) { build_simple_article }

      it 'returns Thing class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::Thing)
      end
    end

    context 'with an ItemList type' do
      let(:object) { build_simple_article(type: 'ItemList') }

      it 'returns ItemList class' do
        expect(described_class.scraper_for_schema_object(object)).to eq(Html2rss::AutoSource::Scraper::Schema::ItemList)
      end
    end

    context 'with an unsupported type' do
      let(:object) { build_simple_article(type: 'UnsupportedType') }

      before { mock_logging }

      it 'logs debug message and returns nil', :aggregate_failures do
        expect(described_class.scraper_for_schema_object(object)).to be_nil
        expect(Html2rss::Log).to have_received(:debug).with(/Unsupported schema object @type: UnsupportedType/)
      end
    end
  end

  describe '.from' do
    context 'with a Nokogiri::XML::Element' do
      let(:script_tag) { build_script_tag('{"@type": "Article"}').at_css('script') }

      it 'parses the script tag and returns schema objects' do
        expect(described_class.from(script_tag)).to include(hash_including('@type': 'Article'))
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
