# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema do
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
            article_schema_object
          ]
        }
      end

      it 'scrapes the article' do
        expect(array).to include(hash_including('@type': 'Article'))
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
  end
end
