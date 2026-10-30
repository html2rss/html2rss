# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml::EntryDeduplicator do
  subject(:deduplicator) { described_class.new('https://example.com', scraper: scraper_class) }

  let(:scraper_class) { Html2rss::AutoSource::Scraper::SemanticHtml }
  let(:root_node) { Html2rss::SST::Node.build(name: :article) }
  let(:story_url) { Html2rss::Url.from_relative('/news/story', 'https://example.com') }

  let(:build_ranked) do
    lambda do |href: '/news/story', final: 65.0, quality: 75.0, position: 0|
      segment = Html2rss::AutoSource::Segment.build(
        root_node:,
        primary_link: Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href:)),
        strategy: :semantic,
        position:
      )
      Html2rss::Scoring::RankedSegment.new(
        segment:,
        score: Html2rss::Scoring::Score.new(
          composite: final, quality:, junk: 10.0, breakdown: Html2rss::Scoring::Score::EMPTY_BREAKDOWN
        )
      )
    end
  end

  let(:build_article) do
    lambda do |description: nil, image: nil, published_at: nil, categories: [], enclosures: []|
      Html2rss::Article.new(
        title: 'Story', url: story_url, id: 'story', description:, image:, published_at:,
        categories:, enclosures:
      )
    end
  end

  # Builds a ranked entry and stubs the article the deduplicator resolves for it.
  let(:entry) do
    lambda do |article:, position: 0, final: 65.0, quality: 75.0, href: '/news/story'|
      ranked = build_ranked.call(href:, final:, quality:, position:)
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).with(ranked, any_args).and_return(article)
      ranked
    end
  end

  describe '#stronger_entry?' do
    it 'prefers a dated payload over a longer description', :aggregate_failures do
      dated = entry.call(article: build_article.call(published_at: Time.utc(2026, 3, 28)), position: 1)
      wordy = entry.call(article: build_article.call(description: 'one two three four five six'), position: 0)

      expect(deduplicator.stronger_entry?(dated, wordy)).to be(true)
      expect(deduplicator.stronger_entry?(wordy, dated)).to be(false)
    end

    it 'counts alphanumeric description words', :aggregate_failures do
      longer = entry.call(article: build_article.call(description: 'one two three'), position: 1)
      shorter = entry.call(article: build_article.call(description: 'one two'), position: 0)

      expect(deduplicator.stronger_entry?(longer, shorter)).to be(true)
      expect(deduplicator.stronger_entry?(shorter, longer)).to be(false)
    end

    it 'ignores punctuation-only text when counting description words', :aggregate_failures do
      punctuation = entry.call(article: build_article.call(description: '-- !! ??'), position: 0)
      words = entry.call(article: build_article.call(description: 'a b'), position: 1)

      expect(deduplicator.stronger_entry?(words, punctuation)).to be(true)
      expect(deduplicator.stronger_entry?(punctuation, words)).to be(false)
    end

    it 'prefers an image over categories and enclosures', :aggregate_failures do
      with_image = entry.call(article: build_article.call(image: 'https://example.com/a.png'), position: 1)
      rich_lists = entry.call(
        article: build_article.call(categories: %w[a b c d e], enclosures: Array.new(3) { { url: story_url } }),
        position: 0
      )

      expect(deduplicator.stronger_entry?(with_image, rich_lists)).to be(true)
      expect(deduplicator.stronger_entry?(rich_lists, with_image)).to be(false)
    end

    it 'prefers more categories over more enclosures', :aggregate_failures do
      categorized = entry.call(article: build_article.call(categories: %w[a b]), position: 1)
      enclosed = entry.call(article: build_article.call(enclosures: Array.new(3) { { url: story_url } }), position: 0)

      expect(deduplicator.stronger_entry?(categorized, enclosed)).to be(true)
      expect(deduplicator.stronger_entry?(enclosed, categorized)).to be(false)
    end

    it 'prefers more enclosures when everything else in the payload ties', :aggregate_failures do
      two = entry.call(article: build_article.call(enclosures: Array.new(2) { { url: story_url } }), position: 1)
      one = entry.call(article: build_article.call(enclosures: [{ url: story_url }]), position: 0)

      expect(deduplicator.stronger_entry?(two, one)).to be(true)
      expect(deduplicator.stronger_entry?(one, two)).to be(false)
    end

    it 'falls back to the earlier DOM position on a full payload tie', :aggregate_failures do
      earlier = entry.call(article: build_article.call(description: 'same text'), position: 0)
      later = entry.call(article: build_article.call(description: 'same text'), position: 1)

      expect(deduplicator.stronger_entry?(earlier, later)).to be(true)
      expect(deduplicator.stronger_entry?(later, earlier)).to be(false)
    end

    it 'counts description words instead of comparing raw description text', :aggregate_failures do
      alphabetically_later = entry.call(article: build_article.call(description: 'zzz'), position: 0)
      more_words = entry.call(article: build_article.call(description: 'a b c'), position: 1)

      expect(deduplicator.stronger_entry?(more_words, alphabetically_later)).to be(true)
      expect(deduplicator.stronger_entry?(alphabetically_later, more_words)).to be(false)
    end

    it 'counts categories instead of comparing category names', :aggregate_failures do
      two_categories = entry.call(article: build_article.call(categories: %w[a b]), position: 1)
      one_category = entry.call(article: build_article.call(categories: %w[z]), position: 0)

      expect(deduplicator.stronger_entry?(two_categories, one_category)).to be(true)
      expect(deduplicator.stronger_entry?(one_category, two_categories)).to be(false)
    end

    it 'does not let a richer payload outrank a higher final score', :aggregate_failures do
      rich = entry.call(article: build_article.call(published_at: Time.utc(2026, 3, 28), description: 'a b c'),
                        final: 60.0, position: 0)
      higher = entry.call(article: build_article.call, final: 70.0, position: 1)

      expect(deduplicator.stronger_entry?(rich, higher)).to be(false)
      expect(deduplicator.stronger_entry?(higher, rich)).to be(true)
    end

    it 'does not let a richer payload outrank a higher quality score', :aggregate_failures do
      rich = entry.call(article: build_article.call(published_at: Time.utc(2026, 3, 28), description: 'a b c'),
                        quality: 60.0, position: 0)
      higher = entry.call(article: build_article.call, quality: 70.0, position: 1)

      expect(deduplicator.stronger_entry?(rich, higher)).to be(false)
      expect(deduplicator.stronger_entry?(higher, rich)).to be(true)
    end

    it 'prefers an entry whose article resolves over one that does not', :aggregate_failures do
      missing = entry.call(article: nil, position: 0)
      resolved = entry.call(article: build_article.call, position: 1)

      expect(deduplicator.stronger_entry?(resolved, missing)).to be(true)
      expect(deduplicator.stronger_entry?(missing, resolved)).to be(false)
    end
  end

  describe '#call' do
    it 'keeps only the strongest entry per destination' do
      weaker = entry.call(article: build_article.call, final: 60.0, position: 0)
      stronger = entry.call(article: build_article.call, final: 70.0, position: 1)

      expect(deduplicator.call([weaker, stronger])).to eq([stronger])
    end

    it 'keeps the stronger entry regardless of input order' do
      weaker = entry.call(article: build_article.call, final: 60.0, position: 0)
      stronger = entry.call(article: build_article.call, final: 70.0, position: 1)

      expect(deduplicator.call([stronger, weaker])).to eq([stronger])
    end

    it 'keeps entries that point at different destinations', :aggregate_failures do
      first = entry.call(article: build_article.call, href: '/news/first', position: 0)
      second = entry.call(article: build_article.call, href: '/news/second', position: 1)

      expect(deduplicator.call([first, second])).to eq([first, second])
    end

    it 'groups anchorless entries by their resolved article url', :aggregate_failures do
      anchorless = lambda do |position|
        segment = Html2rss::AutoSource::Segment.build(root_node:, primary_link: nil, strategy: :semantic, position:)
        Html2rss::Scoring::RankedSegment.new(
          segment:,
          score: Html2rss::Scoring::Score.new(
            composite: 65.0, quality: 75.0, junk: 10.0, breakdown: Html2rss::Scoring::Score::EMPTY_BREAKDOWN
          )
        )
      end
      first = anchorless.call(0)
      second = anchorless.call(1)
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).with(first, any_args).and_return(build_article.call)
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).with(second, any_args)
                                                                  .and_return(build_article.call(description: 'x'))

      expect(deduplicator.call([first, second]).size).to eq(1)
    end
  end

  describe '#article_for' do
    let(:article) { build_article.call(description: 'Summary') }

    it 'extracts with the page base url, the scraper class and anchorless fallback', :aggregate_failures do
      ranked = build_ranked.call
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).and_return(article)

      expect(deduplicator.article_for(ranked)).to be(article)
      expect(Html2rss::Html::SstArticleExtractor).to have_received(:call).with(
        ranked, base_url: 'https://example.com', scraper: scraper_class, fallback_anchorless: true
      )
    end

    it 'extracts each entry only once' do
      ranked = build_ranked.call
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).and_return(article)

      2.times { deduplicator.article_for(ranked) }

      expect(Html2rss::Html::SstArticleExtractor).to have_received(:call).once
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
