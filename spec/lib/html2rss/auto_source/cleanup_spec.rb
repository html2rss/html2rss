# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Cleanup do
  let(:url) { Html2rss::Url.from_relative('http://example.com', 'http://example.com') }
  let(:articles) do
    [
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article0', 'http://example.com'),
                      title: 'Valid Article One'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article1', 'http://example.com'),
                      title: 'Valid Article Two'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: false,
                      url: Html2rss::Url.from_relative('http://example.com/article2', 'http://example.com'),
                      title: 'Invalid Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://otherdomain.com/article3', 'http://example.com'),
                      title: 'Different Domain Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('ftp://example.com/article4', 'http://example.com'),
                      title: 'Non-HTTP Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article5', 'http://example.com'),
                      title: 'Short')
    ]
  end

  describe '.call' do
    subject { described_class.call(articles, url:, keep_different_domain:, min_words_title:) }

    let(:keep_different_domain) { false }
    let(:min_words_title) { 2 }

    it 'removes invalid articles' do
      expect(subject).not_to include(articles[2])
    end

    context 'with duplicated articles' do
      let(:duplicated_url_article) do
        instance_double(Html2rss::RssBuilder::Article,
                        valid?: true,
                        url: articles.first.url,
                        title: 'Duplicated Article')
      end

      before do
        articles << duplicated_url_article
      end

      it 'removes duplicate articles by URL', :aggregate_failures do
        expect(subject).not_to include(duplicated_url_article)
        expect(subject.first.url).to eq(duplicated_url_article.url)
      end
    end

    it 'keeps only HTTP and HTTPS articles' do
      expect(subject).not_to include(articles[4])
    end

    context 'when keep_different_domain is false' do
      it 'removes articles from different domains' do
        expect(subject).not_to include(articles[3])
      end
    end

    context 'when keep_different_domain is true' do
      let(:keep_different_domain) { true }

      it 'keeps articles from different domains' do
        different_domain_article = articles[3]
        expect(subject).to include(different_domain_article)
      end
    end

    it 'keeps only articles with a title having at least min_words_title words' do
      expect(subject).not_to include(articles[5])
    end
  end

  describe '.keep_only_with_min_words_title!' do
    subject(:keep_only_with_min_words_title!) do
      described_class.keep_only_with_min_words_title!(articles, min_words_title:)
    end

    let(:articles) do
      [
        instance_double(Html2rss::RssBuilder::Article, title: 'A valid title'),
        instance_double(Html2rss::RssBuilder::Article, title: 'Short'),
        instance_double(Html2rss::RssBuilder::Article, title: 'Another valid article title'),
        instance_double(Html2rss::RssBuilder::Article, title: nil),
        instance_double(Html2rss::RssBuilder::Article, title: ''),
        instance_double(Html2rss::RssBuilder::Article, title: 'Two words')
      ]
    end

    context 'when min_words_title is 3' do
      let(:min_words_title) { 3 }

      it 'keeps only articles with at least 3 words in the title or nil title', :aggregate_failures do
        keep_only_with_min_words_title!
        expect(articles.map(&:title)).to contain_exactly('A valid title', 'Another valid article title', nil)
      end
    end

    context 'when min_words_title is 1' do
      let(:min_words_title) { 1 }

      it 'keeps all articles except those with empty string title', :aggregate_failures do
        keep_only_with_min_words_title!
        expect(articles.map(&:title)).to contain_exactly(
          'A valid title', 'Short', 'Another valid article title', nil, 'Two words'
        )
      end
    end

    context 'when all titles are nil or empty' do
      let(:articles) do
        [
          instance_double(Html2rss::RssBuilder::Article, title: nil),
          instance_double(Html2rss::RssBuilder::Article, title: '')
        ]
      end
      let(:min_words_title) { 2 }

      it 'keeps only articles with nil title' do
        keep_only_with_min_words_title!
        expect(articles.map(&:title)).to contain_exactly(nil)
      end
    end
  end
end
