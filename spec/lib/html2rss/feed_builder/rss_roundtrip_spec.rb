# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::Rss do
  describe 'round trip', :property do
    it 'pairs count, order, title, url, published_at, categories, author (both paths) and guid per article',
       :property do
      forall(ArticleGenerators.feed) do |articles|
        expect(RssRoundtrip.actual_fields(articles)).to eq(RssRoundtrip.expected_fields(articles))
      end
    end

    it 'renders any description without raising, keeps visible text and does not prepend the title',
       :aggregate_failures, :property do
      forall(ArticleGenerators.description) do |description|
        parsed = RssRoundtrip.description_of(description, title: 'Headline')
        expect(parsed).not_to start_with('Headline')
        expect(parsed).not_to be_empty unless Nokogiri::HTML5.fragment(description).text.strip.empty?
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
