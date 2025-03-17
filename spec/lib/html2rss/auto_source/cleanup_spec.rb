# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Cleanup do
  let(:url) { Addressable::URI.parse('http://example.com') }
  let(:articles) do
    [
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Addressable::URI.parse('http://example.com/article0'),
                      title: 'Valid Article One'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Addressable::URI.parse('http://example.com/article1'),
                      title: 'Valid Article Two'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: false,
                      url: Addressable::URI.parse('http://example.com/article2'),
                      title: 'Invalid Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Addressable::URI.parse('http://otherdomain.com/article3'),
                      title: 'Different Domain Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Addressable::URI.parse('ftp://example.com/article4'),
                      title: 'Non-HTTP Article'),
      instance_double(Html2rss::RssBuilder::Article,
                      valid?: true,
                      url: Addressable::URI.parse('http://example.com/article5'),
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
end
