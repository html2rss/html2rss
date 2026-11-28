# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::Rss do
  describe 'round trip', :property do
    it 'keeps one item per renderable article, in order' do
      forall(ArticleGenerators.feed) do |articles|
        urls = ->(list) { list.map { _1.url.to_s } }

        expect(urls.call(RssRoundtrip.call(articles))).to eq(urls.call(RssRoundtrip.renderable(articles)))
      end
    end

    it 'pairs the title with each renderable article' do
      forall(ArticleGenerators.feed) do |articles|
        expect(RssRoundtrip.call(articles).map(&:title)).to eq(RssRoundtrip.renderable(articles).map(&:title))
      end
    end

    it 'pairs the publication second with each renderable article' do
      forall(ArticleGenerators.feed) do |articles|
        seconds = ->(list) { list.map { _1.published_at.to_time.to_i } }

        expect(seconds.call(RssRoundtrip.call(articles))).to eq(seconds.call(RssRoundtrip.renderable(articles)))
      end
    end

    it 'pairs the categories with each renderable article' do
      forall(ArticleGenerators.feed) do |articles|
        expect(RssRoundtrip.call(articles).map(&:categories)).to eq(RssRoundtrip.renderable(articles).map(&:categories))
      end
    end

    it 'keeps the wire guid as the parsed id (Article#guid is derived, so it is not re-read)' do
      forall(ArticleGenerators.feed) do |articles|
        expect(RssRoundtrip.hashes(articles).map { _1[:id] }).to eq(RssRoundtrip.renderable(articles).map(&:guid))
      end
    end

    it 'keeps a person name as author via dc:creator' do
      forall(ArticleGenerators.feed(author: ArticleGenerators.person_name)) do |articles|
        expect(RssRoundtrip.call(articles).map(&:author)).to eq(RssRoundtrip.renderable(articles).map(&:author))
      end
    end

    it 'keeps an email address as author via author' do
      forall(ArticleGenerators.feed(author: ArticleGenerators.email_person)) do |articles|
        expect(RssRoundtrip.call(articles).map(&:author)).to eq(RssRoundtrip.renderable(articles).map(&:author))
      end
    end

    it 'renders any description without raising and does not prepend the title' do
      forall(ArticleGenerators.description) do |description|
        article = Html2rss::Article.new(url: 'https://example.com/a', title: 'Headline', description:)

        expect(RssRoundtrip.call([article]).first&.description.to_s).not_to start_with('Headline')
      end
    end

    it 'keeps the plain words of a plain-text description' do
      forall(TextGenerators.words) do |words|
        article = Html2rss::Article.new(url: 'https://example.com/a', title: 'Headline', description: words.join(' '))

        expect(RssRoundtrip.call([article]).first.description).to include(*words)
      end
    end
  end
end
