# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml::EntryDeduplicator do
  subject(:deduplicator) { described_class.new('https://example.com', scraper: scraper_class) }

  let(:scraper_class) { Html2rss::AutoSource::Scraper::SemanticHtml }
  let(:root_node) { Html2rss::Html::SST::Node.build(name: :article) }
  let(:story_url) { Html2rss::Url.from_relative('/news/story', 'https://example.com') }
  let(:episode_url) { Html2rss::Url.from_relative('/news/story.mp3', 'https://example.com') }

  let(:build_ranked) do
    lambda do |href: '/news/story', final: 65.0, quality: 75.0, position: 0, root: root_node|
      segment = Html2rss::AutoSource::Segment.build(
        root_node: root,
        primary_link: Html2rss::Html::SST::Node.build(name: :a, attrs: Html2rss::Html::SST::Attrs.build(href:)),
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
    lambda do |article:, position: 0, final: 65.0, quality: 75.0, href: '/news/story', root: root_node|
      ranked = build_ranked.call(href:, final:, quality:, position:, root:)
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).with(ranked, any_args).and_return(article)
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
        article: build_article.call(categories: %w[a b c d e], enclosures: Array.new(3) { { url: episode_url } }),
        position: 0
      )

      expect(deduplicator.stronger_entry?(with_image, rich_lists)).to be(true)
      expect(deduplicator.stronger_entry?(rich_lists, with_image)).to be(false)
    end

    it 'prefers more categories over more enclosures', :aggregate_failures do
      categorized = entry.call(article: build_article.call(categories: %w[a b]), position: 1)
      enclosed = entry.call(article: build_article.call(enclosures: Array.new(3) { { url: episode_url } }), position: 0)

      expect(deduplicator.stronger_entry?(categorized, enclosed)).to be(true)
      expect(deduplicator.stronger_entry?(enclosed, categorized)).to be(false)
    end

    it 'prefers more enclosures when everything else in the payload ties', :aggregate_failures do
      two = entry.call(article: build_article.call(enclosures: Array.new(2) { { url: episode_url } }), position: 1)
      one = entry.call(article: build_article.call(enclosures: [{ url: episode_url }]), position: 0)

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

    it 'prefers the card nested in another on a score tie, whatever the payload', :aggregate_failures do
      inner = Html2rss::Html::SST::Node.build(name: :div)
      outer = Html2rss::Html::SST::Node.build(name: :section, children: [inner])
      swollen = entry.call(article: build_article.call(description: 'one two three four'), root: outer, position: 0)
      tight = entry.call(article: build_article.call(description: 'one'), root: inner, position: 1)

      expect(deduplicator.stronger_entry?(tight, swollen)).to be(true)
      expect(deduplicator.stronger_entry?(swollen, tight)).to be(false)
    end

    {
      'a date' => { published_at: Time.utc(2026, 3, 28) },
      'an image' => { image: 'https://example.com/a.jpg' },
      'a category' => { categories: %w[city] },
      'an enclosure' => { enclosures: [{ url: Html2rss::Url.from_absolute('https://example.com/a.mp3') }] }
    }.each do |label, fields|
      it "keeps a container that carries #{label} the nested card lacks", :aggregate_failures do
        inner = Html2rss::Html::SST::Node.build(name: :div)
        outer = Html2rss::Html::SST::Node.build(name: :section, children: [inner])
        real = entry.call(article: build_article.call(**fields), root: outer, position: 1)
        bare = entry.call(article: build_article.call, root: inner, position: 0)

        expect(deduplicator.stronger_entry?(real, bare)).to be(true)
        expect(deduplicator.stronger_entry?(bare, real)).to be(false)
      end
    end

    it 'lets the payload decide between a container with structured fields and a wordier nested card',
       :aggregate_failures do
      inner = Html2rss::Html::SST::Node.build(name: :div)
      outer = Html2rss::Html::SST::Node.build(name: :section, children: [inner])
      real = entry.call(article: build_article.call(categories: %w[city]), root: outer, position: 1)
      wordy = entry.call(article: build_article.call(description: 'one two three'), root: inner, position: 0)

      expect(deduplicator.stronger_entry?(wordy, real)).to be(true)
      expect(deduplicator.stronger_entry?(real, wordy)).to be(false)
    end

    it 'prefers a container with an article over a nested card without one', :aggregate_failures do
      inner = Html2rss::Html::SST::Node.build(name: :div)
      outer = Html2rss::Html::SST::Node.build(name: :section, children: [inner])
      real = entry.call(article: build_article.call, root: outer, position: 1)
      none = entry.call(article: nil, root: inner, position: 0)

      expect(deduplicator.stronger_entry?(real, none)).to be(true)
      expect(deduplicator.stronger_entry?(none, real)).to be(false)
    end

    it 'compares the payload of cards that do not nest', :aggregate_failures do
      div = -> { Html2rss::Html::SST::Node.build(name: :div) }
      left = entry.call(article: build_article.call(description: 'one two'), root: div.call, position: 1)
      right = entry.call(article: build_article.call(description: 'one'), root: div.call, position: 0)

      expect(deduplicator.stronger_entry?(left, right)).to be(true)
      expect(deduplicator.stronger_entry?(right, left)).to be(false)
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
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).with(first,
                                                                           any_args).and_return(build_article.call)
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).with(second, any_args)
                                                                     .and_return(build_article.call(description: 'x'))

      expect(deduplicator.call([first, second]).size).to eq(1)
    end
  end

  describe '#article_for' do
    let(:article) { build_article.call(description: 'Summary') }

    it 'extracts with the page base url and the scraper class', :aggregate_failures do
      ranked = build_ranked.call
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).and_return(article)

      expect(deduplicator.article_for(ranked)).to be(article)
      expect(Html2rss::AutoSource::ArticleExtractor).to have_received(:call).with(
        ranked, base_url: 'https://example.com', time_zone: nil, scraper: scraper_class,
                link_resolver: be_a(Html2rss::Scoring::LinkResolver)
      )
    end

    it 'extracts with the channel time zone', :aggregate_failures do
      ranked = build_ranked.call
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).and_return(article)

      described_class.new('https://example.com', scraper: scraper_class, time_zone: 'Europe/Berlin')
                     .article_for(ranked)

      expect(Html2rss::AutoSource::ArticleExtractor).to have_received(:call)
        .with(ranked, hash_including(time_zone: 'Europe/Berlin'))
    end

    it 'extracts with the page resolver, which carries the page language', :aggregate_failures do
      resolver = Html2rss::Scoring::LinkResolver.new('https://example.com', vocabulary: Html2rss::Vocabulary['zh-Hant'])
      ranked = build_ranked.call
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).and_return(article)

      described_class.new('https://example.com', scraper: scraper_class, link_resolver: resolver).article_for(ranked)

      expect(Html2rss::AutoSource::ArticleExtractor).to have_received(:call).with(
        ranked, base_url: 'https://example.com', time_zone: nil, scraper: scraper_class, link_resolver: resolver
      )
    end

    it 'extracts each entry only once' do
      ranked = build_ranked.call
      allow(Html2rss::AutoSource::ArticleExtractor).to receive(:call).and_return(article)

      2.times { deduplicator.article_for(ranked) }

      expect(Html2rss::AutoSource::ArticleExtractor).to have_received(:call).once
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
