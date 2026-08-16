# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Cleanup do
  let(:url) { Html2rss::Url.from_absolute('http://example.com') }
  let(:articles) do
    [
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article0', 'http://example.com'),
                      title: 'Valid Article One'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article1', 'http://example.com'),
                      title: 'Valid Article Two'),
      instance_double(Html2rss::Article,
                      valid?: false,
                      url: Html2rss::Url.from_relative('http://example.com/article2', 'http://example.com'),
                      title: 'Invalid Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://otherdomain.com/article3', 'http://example.com'),
                      title: 'Different Domain Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('ftp://example.com/article4', 'http://example.com'),
                      title: 'Non-HTTP Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article5', 'http://example.com'),
                      title: 'Short')
    ]
  end

  describe '.call' do
    subject(:cleaned) { described_class.call(articles, url:, keep_different_domain:) }

    let(:keep_different_domain) { false }

    it 'removes invalid articles' do
      expect(cleaned).not_to include(articles[2])
    end

    context 'with duplicated articles' do
      let(:duplicated_url_article) do
        instance_double(Html2rss::Article,
                        valid?: true,
                        url: articles.first.url,
                        title: 'Duplicated Article Title')
      end

      before { articles << duplicated_url_article }

      it 'removes duplicate articles by URL', :aggregate_failures do
        expect(cleaned).not_to include(duplicated_url_article)
        expect(cleaned.first.url).to eq(duplicated_url_article.url)
      end
    end

    context 'when URLs differ only by fragment' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/news') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/story-one'),
                          title: 'First Story Title Here'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/story-one#comments'),
                          title: 'Same Story Different Fragment'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/news#section'),
                          title: 'Self Link With Fragment Text'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/news'),
                          title: 'Exact Self Link Title Words')
        ]
      end

      it 'dedupes fragment variants and rejects page self-links', :aggregate_failures do
        expect(cleaned.map { |article| article.url.to_s }).to eq(['http://example.com/story-one'])
        expect(cleaned.size).to eq(1)
      end
    end

    it 'keeps only HTTP and HTTPS articles' do
      expect(cleaned).not_to include(articles[4])
    end

    context 'when keep_different_domain is false' do
      it 'removes articles from different domains' do
        expect(cleaned).not_to include(articles[3])
      end
    end

    context 'when keep_different_domain is true' do
      let(:keep_different_domain) { true }

      it 'keeps articles from different domains' do
        different_domain_article = articles[3]
        expect(cleaned).to include(different_domain_article)
      end
    end

    it 'rejects titles with fewer than three words' do
      expect(cleaned).not_to include(articles[5])
    end

    context 'with junk and acceptable titles' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/list') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/a'),
                          title: 'A valid title'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/b'),
                          title: 'Getty Images'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/c'),
                          title: 'Photo: Reuters'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/d'),
                          title: 'lucy.smith.token'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/e'),
                          title: 'methode-article-slug'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/f'),
                          title: nil),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/g'),
                          title: 'Reuters reports major breakthrough today')
        ]
      end

      it 'rejects credit/CMS junk while keeping real headlines and nil titles', :aggregate_failures do
        titles = cleaned.map(&:title)
        expect(titles).to include('A valid title', nil, 'Reuters reports major breakthrough today')
        expect(titles).not_to include('Getty Images', 'Photo: Reuters', 'lucy.smith.token', 'methode-article-slug')
      end
    end

    context 'with slug, date-path, and natural titles' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/list') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/slug'),
                          title: 'breakdancerin-raygun-geht-weiter-110168077'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/titleized'),
                          title: 'Breakdancerin Raygun Geht Weiter 110168077'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/date'),
                          title: '2026 08 16 World Europe Some Article Slug'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/jobs'),
                          title: 'Jobs in Berlin'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/leicht'),
                          title: '5 Wahrheiten über die deutsche Leichtathletik')
        ]
      end

      it 'rejects slug/token-shaped titles while keeping natural headlines', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        titles = cleaned.map(&:title)
        expect(titles).to include('Jobs in Berlin', '5 Wahrheiten über die deutsche Leichtathletik')
        expect(titles).not_to include(
          'breakdancerin-raygun-geht-weiter-110168077',
          'Breakdancerin Raygun Geht Weiter 110168077',
          '2026 08 16 World Europe Some Article Slug'
        )
      end
    end

    context 'with non-Latin titles' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/list') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/ru'),
                          title: 'Привет мир сегодня'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/ar'),
                          title: 'مرحبا بالعالم اليوم'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/zh'),
                          title: '你好世界')
        ]
      end

      it 'counts Unicode words with the fixed three-word gate', :aggregate_failures do
        titles = cleaned.map(&:title)
        expect(titles).to include('Привет мир сегодня', 'مرحبا بالعالم اليوم')
        expect(titles).not_to include('你好世界')
      end
    end
  end
end
