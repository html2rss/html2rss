# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::JsonLd do
  let(:news_article) do
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

  let(:article) do
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

  describe '.self.article_objects(object)' do
    subject(:array) { described_class.article_objects(object) }

    context 'with nil' do
      let(:object) { nil }

      it 'extracts the article' do
        expect(array).to eq([])
      end
    end

    context 'with a single Article object' do
      let(:object) { article }

      it 'extracts the article' do
        expect(array).to include(hash_including('@type': 'Article'))
      end
    end

    context 'with an ItemList object' do
      let(:object) do
        {
          '@context': 'https://schema.org',
          '@type': 'ItemList',
          itemListElement: [
            article
          ]
        }
      end

      it 'extracts the article' do
        expect(array).to include(hash_including('@type': 'Article'))
      end
    end

    context 'with a deeply nested object' do
      let(:object) do
        {
          foo: [
            {
              bar: [news_article]
            }
          ]
        }
      end

      it 'extracts the NewsArticle' do
        expect(array).to include(hash_including('@type': 'NewsArticle'))
      end
    end
  end

  describe '.articles?(parsed_body)' do
    subject(:articles?) { described_class.articles?(parsed_body) }

    context 'with a NewsArticle' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{news_article.to_json}</script>")
      end

      it { is_expected.to be_truthy }
    end

    context 'with an Article' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{article.to_json}</script>")
      end

      it { is_expected.to be_truthy }
    end

    context 'with an empty body' do
      let(:parsed_body) { Nokogiri::HTML.fragment('') }

      it { is_expected.to be_falsey }
    end
  end

  describe '.supported_type?(string)' do
    subject(:supported_type?) { described_class.supported_type?(string) }

    context 'with a NewsArticle' do
      let(:string) { news_article.to_json }

      it { is_expected.to be_truthy }
    end

    context 'with an Article' do
      let(:string) { article.to_json }

      it { is_expected.to be_truthy }
    end

    context 'with an empty string' do
      let(:string) { '' }

      it { is_expected.to be_falsey }
    end

    context 'with a string without @type' do
      let(:string) { { foo: 'bar' }.to_json }

      it { is_expected.to be_falsey }
    end
  end

  describe '.extract(article)' do
    context 'with a NewsArticle' do
      subject(:extract) { described_class.extract(news_article, url: '') }

      it 'extracts the article' do # rubocop:disable RSpec/ExampleLength
        expect(extract).to match(
          title: "Trump Russia claims: FBI's Comey confirms investigation of election 'interference'",
          url: Addressable::URI,
          image: 'http://ichef-1.bbci.co.uk/news/560/media/images/75306000/jpg/_75306515_line976.jpg',
          article_body: "Director Comey says the probe into last year's US election " \
                        'would assess if crimes were committed.',
          abstract: nil,
          description: nil,
          id: '/news/world-us-canada-39324587',
          published_at: DateTime.parse('2017-03-20T20:30:54+00:00')
        )
      end
    end

    context 'with an Article' do
      subject(:extract) { described_class.extract(article, url: '') }

      it 'extracts the article' do # rubocop:disable RSpec/ExampleLength
        expect(extract).to match(
          title: 'Für Einsparungen kündigt Google komplettem Python-Team',
          url: Addressable::URI,
          image: 'https://www.heise.de/imgs/18/4/5/8/2/0/6/6/shutterstock_1777981682-958a1d575a8f5e3e.jpeg',
          description: nil,
          abstract: 'Einem Python-Team wurde offenbar komplett gekündigt.',
          published_at: nil,
          id: '4582066'
        )
      end
    end
  end

  describe '.call' do
    subject(:call) { described_class.new(parsed_body, url: '').call }

    context 'with a NewsArticle' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{news_article.to_json}</script>")
      end

      it 'extracts the article' do
        expect(call).to include(
          hash_including(
            title: "Trump Russia claims: FBI's Comey confirms investigation of election 'interference'"
          )
        )
      end
    end

    context 'with an Article' do
      let(:parsed_body) do
        Nokogiri::HTML("<script type=\"application/ld+json\">#{article.to_json}</script>")
      end

      it 'extracts the article' do
        expect(call).to include(hash_including(title: 'Für Einsparungen kündigt Google komplettem Python-Team'))
      end
    end

    context 'with an empty body' do
      let(:parsed_body) { Nokogiri::HTML('') }

      it 'returns an empty array' do
        expect(call).to eq([])
      end
    end

    context 'with an unsupported @type' do
      let(:parsed_body) { Nokogiri::HTML('<script type="application/ld+json">{"@type": "foo"}</script>') }

      it 'returns an empty array' do
        expect(call).to eq([])
      end
    end
  end
end
