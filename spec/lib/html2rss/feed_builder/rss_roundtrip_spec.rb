# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::Rss do
  describe 'round trip', :property do
    it 'keeps title and url and one item per article', :aggregate_failures do
      forall(ArticleGenerators.article) do |article|
        back = RssRoundtrip.call([article])

        expect(back.map(&:title)).to eq([article.title])
        expect(back.map { _1.url.to_s }).to eq([article.url.to_s])
      end
    end

    it 'keeps the publication second and the categories', :aggregate_failures do
      forall(ArticleGenerators.article) do |article|
        back = RssRoundtrip.call([article]).first

        expect(back.published_at.to_time.to_i).to eq(article.published_at.to_time.to_i)
        expect(back.categories).to eq(article.categories)
      end
    end

    it 'keeps the wire guid as the parsed id (Article#guid is derived, so it is not re-read)' do
      forall(ArticleGenerators.article) do |article|
        expect(RssRoundtrip.hashes([article]).first[:id]).to eq(article.guid)
      end
    end

    it 'keeps a person name as author via dc:creator', :aggregate_failures do
      forall(ArticleGenerators.article(author: ArticleGenerators.person_name)) do |article|
        expect(RssRoundtrip.call([article]).first.author).to eq(article.author)
      end
    end

    it 'keeps an email address as author via author', :aggregate_failures do
      forall(ArticleGenerators.article(author: ArticleGenerators.email_person)) do |article|
        expect(RssRoundtrip.call([article]).first.author).to eq(article.author)
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
