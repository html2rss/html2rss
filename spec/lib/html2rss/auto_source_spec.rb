# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

require_relative '../../support/saved_responses'

RSpec.describe Html2rss::AutoSource do
  subject(:auto_source) { described_class.new(response, config, request_session:) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:response) { Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/html' }, url:) }
  let(:request_session) { nil }
  let(:body) do
    <<~HTML
      <html>
        <body>
          <article id="article-1">
            <h2>Article 1 Title <!-- remove this --></h2>
            <p>This is some teaser content about Article 1.</p>
            <a href="/article1">Read more</a>
          </article>
        </body>
      </html>
    HTML
  end

  describe '::DEFAULT_CONFIG' do
    subject(:default_config) { described_class::DEFAULT_CONFIG }

    it 'is a frozen Hash' do
      expect(default_config).to be_a(Hash).and be_frozen
    end
  end

  describe '::DEFAULT_LIMIT' do
    it 'defaults to twenty-five articles' do
      expect(described_class::DEFAULT_LIMIT).to eq(25)
    end
  end

  describe Html2rss::Config::AutoSourceContract do
    subject(:schema) { described_class }

    it 'validates the default config' do
      expect(schema.call(Html2rss::AutoSource::DEFAULT_CONFIG)).to be_success
    end

    it 'allows overriding limit' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(limit: 10)

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the json_state scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(json_state: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the json_document scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(json_document: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the wordpress_api scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(wordpress_api: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the microdata scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(microdata: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    describe 'optional(:cleanup)' do
      let(:config) do
        config = Html2rss::AutoSource::DEFAULT_CONFIG.dup
        config[:auto_source] = { cleanup: Html2rss::AutoSource::Cleanup::DEFAULT_CONFIG }
        config
      end

      it 'validates cleanup defaults' do
        expect(schema.call(config)).to be_success
      end
    end
  end

  describe '#articles' do
    subject(:articles) { auto_source.articles }

    describe 'when scraping succeeds' do
      subject(:article) { articles.first }

      it 'returns a single Html2rss::Article', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(article).to be_a(Html2rss::Article)
      end

      it 'preserves article content', :aggregate_failures do
        expect(article.title).to eq('Article 1 Title')
        expect(article.id).to eq('article-1')
        expect(article.description).to eq('This is some teaser content about Article 1.')
        expect(article.scraper).to eq(Html2rss::AutoSource::Scraper::SemanticHtml)
      end

      it 'sanitizes the article url' do
        expected_url = Html2rss::Url.from_absolute('https://example.com/article1')
        expect(article.url).to eq(expected_url)
      end
    end

    context 'when no scrapers are found' do
      let(:body) { '<html><body></body></html>' }

      before { allow(Html2rss::Log).to receive(:warn) }

      # rubocop:disable-next RSpec/ExampleLength -- structured event_name + host + category assert
      it 'logs a warning and returns an empty array', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          parsed = JSON.parse(payload)
          expect(parsed).to include(
            'event_name' => 'auto_source.no_scraper',
            'host' => url.host,
            'category' => 'unsupported_surface'
          )
          expect(parsed['message']).to include("#{described_class}: no scraper matched #{url}")
        end
      end
    end

    context 'when structured items reach the limit only before Cleanup' do
      let(:config) { described_class::DEFAULT_CONFIG.merge(limit: 3) }
      let(:body) do
        headlines = ['Schema story number one', 'Schema story number two', 'Too short']
        items = headlines.each_with_index.map do |headline, index|
          { '@type' => 'NewsArticle', 'headline' => headline, 'url' => "https://example.com/news/schema-#{index}" }
        end
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => items }
        list = items.map { %(<li><a href="#{_1['url']}">#{_1['headline']}</a></li>) }.join
        card = '<article><h2><a href="/news/page-story">Page story read by the heuristic tier</a></h2></article>'
        %(<html><body><script type="application/ld+json">#{ld.to_json}</script><ul>#{list}</ul>#{card}</body></html>)
      end

      it 'counts admitted items only and reads the heuristic tier' do
        expect(articles.map { _1.url.path }).to include('/news/page-story')
      end
    end

    context 'when a matching scraper yields nothing' do
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => [] }
        %(<html><body><script type="application/ld+json">#{ld.to_json}</script><p>Quiet page.</p></body></html>)
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'does not warn that admission emptied the capture' do
        articles
        expect(Html2rss::Log).not_to have_received(:warn).with(/admission_emptied/)
      end
    end

    context 'when the response body is empty' do
      let(:body) { '' }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'returns an empty array without raising' do
        expect(articles).to eq([])
      end
    end

    context 'with custom configuration that disables matching scrapers' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) },
          cleanup: { keep_different_domain: true }
        )
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'returns no articles when every scraper is disabled' do
        expect(articles).to eq([])
      end
    end

    context 'when structured scrapers already yield enough articles' do
      let(:schema_items) do
        Array.new(6) do |index|
          {
            '@type' => 'NewsArticle',
            'headline' => "Schema Story #{index} Extra Words Here",
            'url' => "https://example.com/schema-#{index}",
            'description' => 'summary'
          }
        end
      end
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => schema_items }
        rendered = schema_items.map { |item| %(<li><a href="#{item['url']}">#{item['headline']}</a></li>) }.join
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
            <ul>#{rendered}</ul>
            <article><h2><a href="/sem-0">Semantic Story 0 Extra Words</a></h2><p>teaser</p></article>
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].merge(
            microdata: { enabled: false },
            microformats2: { enabled: false },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            meta_oembed: { enabled: false }
          )
        )
      end

      it 'never builds the heuristic tier, also when the items exactly fill the limit', :aggregate_failures do
        allow(Html2rss::AutoSource::Scraper::SemanticHtml).to receive(:new).and_call_original
        articles
        described_class.new(response, config.merge(limit: schema_items.size)).articles
        expect(Html2rss::AutoSource::Scraper::SemanticHtml).not_to have_received(:new)
      end

      it 'keeps Schema articles and skips heuristic titles', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Schema Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::Schema))
        expect(articles.map { |article| article.url.to_s }).to eq(
          Array.new(5) { |index| "https://example.com/schema-#{index}" }
        )
      end
    end

    context 'when structured articles fail Cleanup title floor' do
      let(:schema_items) do
        Array.new(5) do |index|
          {
            '@type' => 'NewsArticle',
            'headline' => 'News',
            'url' => "https://example.com/thin-#{index}",
            'description' => 'summary'
          }
        end
      end
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => schema_items }
        semantic = Array.new(5) do |index|
          <<~HTML
            <article>
              <h2><a href="/sem-#{index}">Semantic Story #{index} Extra Words</a></h2>
              <p>This is teaser content about the story.</p>
            </article>
          HTML
        end.join
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
            #{semantic}
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].merge(
            microdata: { enabled: false },
            microformats2: { enabled: false },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            meta_oembed: { enabled: false },
            html: described_class::DEFAULT_CONFIG[:scraper][:html].merge(enabled: false)
          )
        )
      end

      it 'continues into heuristics so Cleanup does not empty the feed', :aggregate_failures do
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Semantic Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::SemanticHtml))
      end
    end

    context 'with options lacking a scraper map' do
      let(:config) { { limit: 5 } }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'enables no scraper and returns no articles' do
        expect(articles).to eq([])
      end
    end

    context 'when chrome-only structured items would fill a small limit' do
      let(:teasers) { %w[harbor-ferry-route-returns library-extends-weekend-hours river-cleanup-volunteers-record] }
      let(:state) do
        menu = %w[world local science].map { |slug| { title: "#{slug.capitalize} affairs desk", url: "/#{slug}/" } }
        lead = { title: 'Harbor ferry route returns after repairs', url: "/news/2026/10/#{teasers.first}",
                 description: 'State copy of the lead story.' }
        { props: { pageProps: { navigation: [*menu, lead] } } }
      end
      let(:body) do
        nav = %w[world local science].map { |slug| %(<a href="/#{slug}/">#{slug.capitalize} affairs desk</a>) }.join
        cards = teasers.map do |slug|
          %(<article><h2><a href="/news/2026/10/#{slug}">#{slug.tr('-', ' ').capitalize}</a></h2>
            <p>Rendered teaser text for this story.</p></article>)
        end.join
        <<~HTML
          <html><body><nav>#{nav}</nav><main>#{cards}</main>
            <script id="__NEXT_DATA__" type="application/json">#{state.to_json}</script>
          </body></html>
        HTML
      end
      let(:config) { described_class::DEFAULT_CONFIG.merge(limit: 3) }

      it 'drops them as chrome_only, runs SemanticHtml, and keeps the structured copy of a shared URL',
         :aggregate_failures do
        expect(articles.map { |article| article.url.path }).to eq(teasers.map { "/news/2026/10/#{_1}" })
        expect(articles.map(&:scraper)).to eq([Html2rss::AutoSource::Scraper::JsonState,
                                               *[Html2rss::AutoSource::Scraper::SemanticHtml] * 2])
        expect(articles.first.description).to eq('State copy of the lead story.')
        expect(auto_source.admission_drops).to include('chrome_only' => 3, 'duplicate_url' => 1)
      end
    end

    context 'with ad-labelled cards' do
      let(:body) { File.read('spec/fixtures/auto_source/corpus/sponsored_ad_label_card.html') }
      let(:sponsored_paths) do
        %w[mattress-sale-ends-friday smart-thermostat-bundle-offer].map { "/news/2026/11/#{_1}" }
      end

      it 'drops the sponsored items and tallies them', :aggregate_failures do
        expect(articles.map { _1.url.path }).not_to include(*sponsored_paths)
        expect(articles.size).to eq(4)
        expect(auto_source.admission_drops).to include('sponsored' => 2)
      end

      it 'admits the sponsored items when cleanup keeps them', :aggregate_failures do
        kept = described_class.new(response, described_class::DEFAULT_CONFIG.merge(cleanup: { keep_sponsored: true }))

        expect(kept.articles.map { _1.url.path }).to include(*sponsored_paths)
        expect(kept.admission_drops).not_to have_key('sponsored')
      end
    end

    context 'when structured items and a heuristic tier share one page' do
      let(:counts) { Hash.new(0) }
      let(:native_feed) do
        item = { title: 'Native feed story title', url: 'https://example.com/news/feed-1', id: 'feed-1' }
        instance_double(Html2rss::AutoSource::Scraper::NativeFeed, extractable?: true).tap do |feed|
          allow(feed).to receive(:map) { |&block| [item].map(&block) }
        end
      end
      let(:body) do
        items = Array.new(2) do |index|
          { '@type' => 'NewsArticle', 'headline' => "Schema story #{index} words", 'url' => "/news/s-#{index}" }
        end
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => items }
        cards = Array.new(3) do |index|
          %(<article><h2><a href="/news/s-#{index}">Schema story #{index} words</a></h2></article>)
        end
        %(<html><body><script type="application/ld+json">#{ld.to_json}</script><main>#{cards.join}</main></body></html>)
      end

      before do
        allow(Html2rss::SST::Normalizer).to receive(:call).and_wrap_original do |method, *args|
          counts[:sst] += 1
          method.call(*args)
        end
        allow(Html2rss::Scoring::LinkResolver).to receive(:new).and_wrap_original do |method, *args|
          counts[:resolver] += 1
          method.call(*args)
        end
      end

      it 'builds the SST and link resolver once for the page check and the heuristic tiers', :aggregate_failures do
        expect(articles.map(&:scraper).tally)
          .to eq(Html2rss::AutoSource::Scraper::Schema => 2, Html2rss::AutoSource::Scraper::SemanticHtml => 1)
        expect(counts).to eq(sst: 1, resolver: 1)
      end

      it 'builds the SST once to check a native feed that fills the limit for sponsorship', :aggregate_failures do
        allow(Html2rss::AutoSource::Scraper::NativeFeed).to receive(:new).and_return(native_feed)
        limited = described_class.new(response, described_class::DEFAULT_CONFIG.merge(limit: 1)).articles

        expect(limited.map { _1.url.path }).to eq(['/news/feed-1'])
        expect(counts[:sst]).to eq(1)
      end
    end

    context 'when structured items of the limit are kept by score but not shown on the page' do
      let(:config) { described_class::DEFAULT_CONFIG.merge(limit: 3) }
      let(:body) do
        items = Array.new(3) do |index|
          { '@type' => 'NewsArticle', 'headline' => "Archive story number #{index}", 'datePublished' => '2026-11-01',
            'image' => "https://example.com/img/#{index}.jpg", 'description' => 'Archive summary.',
            'url' => "https://example.com/news/2026/11/archive-story-#{index}" }
        end
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => items }
        cards = Array.new(3) do |index|
          %(<article><h2><a href="/news/2026/11/page-story-#{index}">Page story number #{index}</a></h2></article>)
        end
        %(<html><body><script type="application/ld+json">#{ld.to_json}</script><main>#{cards.join}</main></body></html>)
      end

      it 'reads the page tiers and puts the shown items first' do
        expect(articles.map { _1.url.path }).to eq(Array.new(3) { "/news/2026/11/page-story-#{_1}" })
      end
    end

    context 'with a few audio items shown among more news cards' do
      let(:config) { described_class::DEFAULT_CONFIG.merge(limit: 3) }
      let(:body) do
        audio = Array.new(3) do |index|
          { '@type' => 'ListItem', 'item' => { '@type' => 'AudioObject', 'name' => "Audio briefing number #{index}",
                                               'url' => "https://example.com/audio/briefing-#{index}" } }
        end
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => audio }
        links = audio.map { %(<li><a href="#{_1['item']['url']}">#{_1['item']['name']}</a></li>) }.join
        cards = Array.new(4) do |index|
          %(<article><h2><a href="/news/2026/11/story-#{index}">News story number #{index}</a></h2></article>)
        end
        script = %(<script type="application/ld+json">#{ld.to_json}</script>)
        %(<html><body>#{script}<main><ul>#{links}</ul>#{cards.join}</main></body></html>)
      end

      it 'is no media page: the audio items do not stop the tiers and the news comes first' do
        expect(articles.map { _1.url.path }).to eq(Array.new(3) { "/news/2026/11/story-#{_1}" })
      end
    end

    context 'with six audio cards in main among ten news cards' do
      let(:body) { File.read('spec/fixtures/auto_source/corpus/t6_media_minority_in_main.html') }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/news/') }

      it 'is no media page: the news comes first, then the audio items', :aggregate_failures do
        expect(articles.first(10).map(&:media?)).to all(be(false))
        expect(articles.drop(10).map(&:media?)).to eq([true] * 6)
      end
    end

    context 'with schema media items rendered in main beside news cards' do
      let(:media_body) do
        lambda do |news:, media:, type:, news_first:|
          items = Array.new(media) do |index|
            { '@type' => 'ListItem', 'item' => { '@type' => type, 'name' => "#{type} item number #{index}",
                                                 'url' => "https://example.com/media/item-#{index}" } }
          end
          ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => items }
          list = "<ul>#{items.map { %(<li><a href="#{_1['item']['url']}">#{_1['item']['name']}</a></li>) }.join}</ul>"
          cards = Array.new(news) do |index|
            %(<article><h2><a href="/news/2026/11/story-#{index}">News story number #{index}</a></h2></article>)
          end.join
          main = news_first ? cards + list : list + cards
          %(<html><body><script type="application/ld+json">#{ld.to_json}</script><main>#{main}</main></body></html>)
        end
      end
      let(:news_paths) { ->(count) { Array.new(count) { "/news/2026/11/story-#{_1}" } } }
      let(:media_paths) { ->(count) { Array.new(count) { "/media/item-#{_1}" } } }

      it 'puts the media of a media page first, then the news, each in document order' do
        allow(response).to receive(:body).and_return(media_body.call(news: 8, media: 12, type: 'VideoObject',
                                                                     news_first: true))
        expect(articles.map { _1.url.path }).to eq(media_paths[12] + news_paths[8])
      end

      it 'is a media page when the media are more than half of the shown cards, so media fill the limit' do
        allow(response).to receive(:body).and_return(media_body.call(news: 10, media: 25, type: 'AudioObject',
                                                                     news_first: false))
        expect(articles.map { _1.url.path }).to eq(media_paths[25])
      end
    end

    context 'with a podcast page of episodes and promo cards' do
      let(:body) { File.read('spec/fixtures/auto_source/corpus/t6_podcast_episode_page.html') }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/podcasts/harbor-hour/') }

      it 'counts the episodes and keeps the first ones in page order' do
        expect(articles.map { _1.url.path }).to eq((1..25).map { "/podcasts/harbor-hour/episode-#{_1}" })
      end
    end

    context 'with a Schema audio list of the item limit beside a news list' do
      let(:body) { File.read('spec/fixtures/auto_source/corpus/t6_media_list_news.html') }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/news/') }

      it 'reads the news before the media items, which fill the rest of the limit', :aggregate_failures do
        news, media = articles.partition { _1.url.path.start_with?('/news/2026/') }

        expect(articles.size).to eq(described_class::DEFAULT_LIMIT)
        expect(news.size).to eq(10)
        expect(articles.first(10)).to eq(news)
        expect(media).to all(be_media)
      end
    end

    context 'with a native feed and a page of cards' do
      let(:dir) { 'spec/fixtures/auto_source/corpus/t6_feed_merge' }
      let(:body) { File.read("#{dir}.html") }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/news/') }
      let(:request_session) { SavedResponses.new(dir) }
      let(:slugs) { articles.map { _1.url.path.delete_prefix('/news/2026/11/') } }
      let(:feed_items) { articles.select { _1.scraper == Html2rss::AutoSource::Scraper::NativeFeed } }

      it 'keeps what the followed feed states about its channel', :aggregate_failures do
        expect(auto_source.feed_channel).to be_nil
        auto_source.articles
        expect(auto_source.feed_channel).to eq(Html2rss::Syndication::ChannelFacts.new)
      end

      it 'puts the feed items first and fills up with page items', :aggregate_failures do
        expect(slugs).to eq(%w[feed-only-council-vote harbor-ferry-schedule library-reading-week river-path-reopens
                               night-market-vendors school-garden-harvest bridge-paint-survey museum-late-opening])
        expect(feed_items.size).to eq(4)
      end

      it 'drops the sponsored feed item', :aggregate_failures do
        expect(slugs).not_to include('partner-energy-savings')
        expect(auto_source.admission_drops).to include('sponsored' => 1, 'duplicate_url' => 4)
      end

      it 'merges each article in both into one feed item carrying the page image', :aggregate_failures do
        merged = feed_items.drop(1)

        expect(merged.map(&:title)).to all(end_with('(publisher title)'))
        slugs = %w[harbor-ferry-schedule library-reading-week river-path-reopens]
        expect(merged.map { _1.image&.path }).to eq(slugs.map { "/img/#{_1}.jpg" })
        expect(feed_items.first.image).to be_nil
      end
    end

    context 'with a podcast feed followed on the hosting platform' do
      let(:dir) { 'spec/fixtures/auto_source/corpus/native_feed_cross_origin_platform_links' }
      let(:body) { File.read("#{dir}.html") }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/news/') }
      let(:request_session) { SavedResponses.new(dir) }

      it "keeps the feed's episodes linking to the platform, their guid or their audio file", :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles.map { _1.url.to_s }).to eq(%w[https://podhost.example.net/harbour-hour/episodes/7-ferry-timetable
                                                      https://podhost.example.net/harbour-hour/episodes/6-lighthouse-keepers
                                                      https://podhost.example.net/harbour-hour/episodes/5-fish-auction
                                                      https://media.example.net/harbour-hour/4.mp3
                                                      https://cdn.audiohost.test/harbour-hour/3.mp3])
        expect(auto_source.admission_drops).to be_empty
      end
    end

    context 'when titles carry leading noise' do
      let(:feed_item) do
        { title: '10:00 Video: Native feed story title', url: 'https://example.com/news/feed-1', id: 'feed-1' }
      end
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => [
          { '@type' => 'NewsArticle', 'headline' => '10:00 Schema story one words', 'url' => '/news/s-1' },
          { '@type' => 'NewsArticle', 'headline' => '10:00 Schema story two words', 'url' => '/news/s-2' }
        ] }
        cards = %w[1 2].map do |index|
          %(<article><h2><a href="/news/s-#{index}">Schema story #{index} words</a></h2></article>)
        end
        %(<html><body><script type="application/ld+json">#{ld.to_json}</script><main>#{cards.join}</main></body></html>)
      end

      let(:declared_scraper) do
        lambda do |klass|
          instance_double(klass, extractable?: true, class: klass).tap do |scraper|
            allow(scraper).to receive(:map) { |&block| [feed_item].map(&block) }
          end
        end
      end

      it 'keeps a publisher-declared structured headline verbatim' do
        schema_titles = articles.select { _1.scraper == Html2rss::AutoSource::Scraper::Schema }.map(&:title)

        expect(schema_titles).to eq(['10:00 Schema story one words', '10:00 Schema story two words'])
      end

      context 'with structured items that carry a kicker' do # rubocop:disable RSpec/NestedGroups -- shares the leading-noise page
        let(:klass) { Html2rss::AutoSource::Scraper::NativeFeed }
        let(:items) do
          [{ title: 'Headline one', kicker: 'Overline', url: 'https://example.com/a', id: 'a' },
           { title: 'Overline: Headline two', kicker: 'overline', url: 'https://example.com/b', id: 'b' },
           { title: '– Headline three words', url: 'https://example.com/c', id: 'c' }]
        end

        before do
          scraper = instance_double(klass, extractable?: true, class: klass)
          allow(scraper).to receive(:map) { |&block| items.map(&block) }
          allow(klass).to receive(:new).and_return(scraper)
        end

        it 'composes the kicker item and keeps the others verbatim' do
          titles = articles.select { _1.scraper == klass }.map(&:title)

          expect(titles).to eq(['Overline: Headline one', 'Overline: Headline two', '– Headline three words'])
        end
      end

      %w[NativeFeed WordpressApi Sitemap MetaOembed].each do |name|
        it "keeps a #{name} title verbatim" do
          klass = Html2rss::AutoSource::Scraper.const_get(name)
          allow(klass).to receive(:new).and_return(declared_scraper.call(klass))

          expect(articles.find { _1.scraper == klass }.title).to eq('10:00 Video: Native feed story title')
        end
      end
    end

    context 'when SemanticHtml is sufficient before Html' do
      let(:articles_html) do
        Array.new(5) do |index|
          <<~HTML
            <article id="a#{index}">
              <h2><a href="/sem-#{index}">Semantic Story #{index} Extra Words</a></h2>
              <p>This is teaser content about the story number #{index}.</p>
            </article>
          HTML
        end.join
      end
      let(:body) { "<html><body>#{articles_html}</body></html>" }
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              semantic_html: { enabled: true },
                                                              html: {
                                                                enabled: true,
                                                                minimum_selector_frequency: 2,
                                                                use_top_selectors: 5
                                                              }
                                                            )
        )
      end

      it 'satisfies the limit from SemanticHtml without Html articles', :aggregate_failures do
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Semantic Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::SemanticHtml))
      end
    end

    context 'when SemanticHtml admits below limit and Html would pad with weaker links' do
      let(:body) do
        semantic = Array.new(2) do |index|
          <<~HTML
            <article id="a#{index}">
              <h2><a href="/news/semantic-story-#{index}-extra-words">Semantic Story #{index} Extra Words</a></h2>
              <p>This is teaser content about the story number #{index}.</p>
            </article>
          HTML
        end.join
        padding = Array.new(8) do |index|
          <<~HTML
            <div class="card card-#{index}">
              <a href="/dating/singles-pad-#{index}">Singles Pad #{index} Find Love Now</a>
            </div>
          HTML
        end.join
        "<html><body>#{semantic}#{padding}</body></html>"
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 10,
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              semantic_html: { enabled: true },
                                                              html: {
                                                                enabled: true,
                                                                minimum_selector_frequency: 2,
                                                                use_top_selectors: 10
                                                              }
                                                            )
        )
      end

      it 'keeps fewer clean SemanticHtml items and does not build Html', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        html_builds = 0
        allow(Html2rss::AutoSource::Scraper).to receive(:build_instance)
          .and_wrap_original do |method, scraper_class, *args, **kwargs|
          html_builds += 1 if scraper_class == Html2rss::AutoSource::Scraper::Html
          method.call(scraper_class, *args, **kwargs)
        end

        expect(articles.size).to eq(2)
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::SemanticHtml))
        expect(articles.map { |article| article.url.to_s }).to all(include('/news/'))
        expect(html_builds).to eq(0)
      end
    end

    context 'when SemanticHtml yields only excluded destinations' do
      let(:body) do
        <<~HTML
          <html><body>
            <article>
              <h2><a href="/dating/singles-only-pad">Singles Only Pad Extra Words</a></h2>
              <p>Affiliate teaser that must not admit into the feed.</p>
            </article>
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              semantic_html: { enabled: true },
                                                              html: {
                                                                enabled: true,
                                                                minimum_selector_frequency: 1,
                                                                use_top_selectors: 5
                                                              }
                                                            )
        )
      end

      it 'still builds Html when prior tiers admit nothing', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        html_builds = 0
        allow(Html2rss::AutoSource::Scraper).to receive(:build_instance)
          .and_wrap_original do |method, scraper_class, *args, **kwargs|
          html_builds += 1 if scraper_class == Html2rss::AutoSource::Scraper::Html
          method.call(scraper_class, *args, **kwargs)
        end

        expect(articles).to eq([])
        expect(html_builds).to eq(1)
      end
    end

    context 'with microdata-only content' do
      subject(:article) { articles.first }

      let(:body) do
        <<~HTML
          <html>
            <body>
              <article itemscope itemtype="https://schema.org/NewsArticle" itemid="story-1">
                <h1 itemprop="headline">Microdata only story</h1>
                <a itemprop="url" href="/microdata-only-story">Read more</a>
                <p itemprop="description">Short summary.</p>
              </article>
            </body>
          </html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: {
            schema: { enabled: false },
            microdata: { enabled: true },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            microformats2: { enabled: false },
            meta_oembed: { enabled: false },
            semantic_html: { enabled: false },
            html: {
              enabled: false,
              minimum_selector_frequency: described_class::DEFAULT_CONFIG.dig(:scraper, :html,
                                                                              :minimum_selector_frequency),
              use_top_selectors: described_class::DEFAULT_CONFIG.dig(:scraper, :html, :use_top_selectors)
            }
          }
        )
      end

      it 'returns Article objects from the Microdata scraper', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(article.title).to eq('Microdata only story')
        expect(article.id).to eq('story-1')
        expect(article.url.to_s).to eq('https://example.com/microdata-only-story')
        expect(article.scraper).to eq(Html2rss::AutoSource::Scraper::Microdata)
      end
    end

    context 'when a scraper raises an operational error' do
      let(:body) do
        ld = {
          '@context' => 'https://schema.org',
          '@type' => 'NewsArticle',
          'headline' => 'Schema Story Extra Words Here',
          'url' => 'https://example.com/schema-1'
        }
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
            <article>
              <h2><a href="/story-one">Semantic Story One Extra Words</a></h2>
              <p>Teaser content for the first semantic story.</p>
            </article>
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              schema: { enabled: true },
                                                              semantic_html: { enabled: true }
                                                            )
        )
      end
      let(:quarantine_log) do
        {
          event_name: 'auto_source.quarantined', host: url.host, error_class: 'ArgumentError',
          message: 'Html2rss::AutoSource: Html2rss::AutoSource::Scraper::Schema quarantined ArgumentError: ' \
                   'bad structured payload'
        }.to_json
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
        allow(Html2rss::AutoSource::Scraper).to receive(:build_instance).and_wrap_original do |method, scraper_class, *args, **kwargs| # rubocop:disable Layout/LineLength
          instance = method.call(scraper_class, *args, **kwargs)
          next instance unless scraper_class == Html2rss::AutoSource::Scraper::Schema && instance

          allow(instance).to receive(:each).and_raise(ArgumentError, 'bad structured payload')
          instance
        end
      end

      it 'quarantines ArgumentError and continues the tier', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(articles.first.scraper).to eq(Html2rss::AutoSource::Scraper::SemanticHtml)
        expect(Html2rss::Log).to have_received(:warn).with(quarantine_log)
      end
    end

    shared_context 'with a lone Schema scraper' do
      let(:body) do
        ld = {
          '@context' => 'https://schema.org',
          '@type' => 'NewsArticle',
          'headline' => 'Schema Story Extra Words Here',
          'url' => 'https://example.com/schema-1'
        }
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(schema: { enabled: true })
        )
      end

      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:build_instance).and_wrap_original do |method, scraper_class, *args, **kwargs| # rubocop:disable Layout/LineLength
          instance = method.call(scraper_class, *args, **kwargs)
          next instance unless scraper_class == Html2rss::AutoSource::Scraper::Schema && instance

          allow(instance).to receive(:each, &schema_each)
          instance
        end
      end
    end

    context 'when a scraper raises an unexpected error' do
      include_context 'with a lone Schema scraper'

      let(:schema_each) { proc { raise StandardError, 'boom' } }

      it 'propagates StandardError instead of quarantining it' do
        expect { articles }.to raise_error(StandardError, 'boom')
      end
    end

    context 'when a scraper yields an item that is neither Article nor Hash' do
      include_context 'with a lone Schema scraper'

      let(:schema_each) { proc { |&block| block.call('not an item') } }

      it 'raises a ScraperContractError naming the scraper instead of quarantining it' do
        expect { articles }
          .to raise_error(described_class::ScraperContractError,
                          'Html2rss::AutoSource::Scraper::Schema yielded String; expected Article or Hash')
      end
    end

    context 'when a scraper raises a non-scraper contract error' do
      include_context 'with a lone Schema scraper'

      let(:schema_each) { proc { raise Html2rss::Status::InvalidError } }

      it 'propagates instead of quarantining the scraper' do
        expect { articles }.to raise_error(Html2rss::Status::InvalidError)
      end
    end

    context 'when the listing is wrapping a.card links (synthetic news shape)' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/daily-briefing') }
      let(:body) do
        cards = [
          ['/daily-briefing/harbor-project-needs-more-attention', 'Harbor project needs more attention today'],
          ['/daily-briefing/northern-region-weather-watch-briefing', 'Northern region weather watch briefing today'],
          ['/daily-briefing/river-council-talks-stall-again', 'River council talks stall again this week']
        ]
        items = cards.map do |href, title|
          <<~CARD
            <a class="card" href="#{href}">
              <div class="card__image"><img src="/img/#{href.split('/').last}.jpg" alt=""></div>
              <div class="card__content">
                <h3>#{title}</h3>
                <p>Teaser line for the daily briefing.</p>
              </div>
            </a>
          CARD
        end.join
        "<!DOCTYPE html><html><body>#{items}</body></html>"
      end

      it 'admits at least one article from the wrapping cards', :aggregate_failures do
        expect(articles.size).to be >= 1
        expect(articles.map { |article| article.url.to_s }).to all(include('/daily-briefing/'))
        expect(articles.map(&:title)).to all(match(/\A\S+(?:\s+\S+){2,}/))
      end
    end

    context 'with a JSON document listing (app list slice)' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/banner/app-list.json') }
      let(:body) { File.read('spec/fixtures/auto_source/json_document/app_list_slice.json') }
      let(:response) do
        Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/json' }, url:)
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'admits nothing by default and logs keep_different_domain', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles).to eq([])
        expect(auto_source.admission_drops).to include('different_domain' => 2)
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          parsed = JSON.parse(payload)
          expect(parsed).to include(
            'event_name' => 'auto_source.admission_emptied',
            'host' => url.host,
            'hint' => Html2rss::AutoSource::Cleanup::DIFFERENT_DOMAIN_HINT,
            'captured_count' => 2
          )
          expect(parsed['drop_tallies']).to include('different_domain' => 2)
        end
      end
    end

    context 'with a JSON document listing keeping different domains' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/banner/app-list.json') }
      let(:body) { File.read('spec/fixtures/auto_source/json_document/app_list_slice.json') }
      let(:response) do
        Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/json' }, url:)
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(cleanup: { keep_different_domain: true })
      end

      it 'keeps the long-named off-domain item without an emptied warning', :aggregate_failures do
        allow(Html2rss::Log).to receive(:warn)
        expect(articles.map(&:title)).to eq(['Long Enough App Name'])
        expect(Html2rss::Log).not_to have_received(:warn)
        expect(articles.first.url.to_s).to eq('https://apps.example.net/app/id1234567890')
        expect(articles.first.scraper).to eq(Html2rss::AutoSource::Scraper::JsonDocument)
      end
    end

    context 'with json_document disabled on a JSON listing' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/banner/app-list.json') }
      let(:body) { File.read('spec/fixtures/auto_source/json_document/app_list_slice.json') }
      let(:response) do
        Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/json' }, url:)
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].merge(json_document: { enabled: false })
        )
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      # rubocop:disable-next RSpec/ExampleLength -- structured event_name + category assert
      it 'logs no_scraper unsupported_surface without classifying HTML', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          parsed = JSON.parse(payload)
          expect(parsed).to include(
            'event_name' => 'auto_source.no_scraper',
            'category' => 'unsupported_surface'
          )
        end
      end
    end

    shared_examples 'scalar JSON unsupported_surface' do |body_json|
      let(:body) { body_json }
      let(:response) do
        Html2rss::RequestService::Response.new(
          body:,
          headers: { 'content-type' => 'application/json' },
          url:
        )
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      # rubocop:disable-next RSpec/ExampleLength -- empty result + structured category assert
      it 'returns empty without raising and logs unsupported_surface', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          parsed = JSON.parse(payload)
          expect(parsed).to include(
            'event_name' => 'auto_source.no_scraper',
            'category' => 'unsupported_surface'
          )
        end
      end
    end

    context 'with scalar JSON null' do
      it_behaves_like 'scalar JSON unsupported_surface', 'null'
    end

    context 'with scalar JSON boolean' do
      it_behaves_like 'scalar JSON unsupported_surface', 'true'
    end

    context 'with scalar JSON number' do
      it_behaves_like 'scalar JSON unsupported_surface', '42'
    end

    context 'with scalar JSON string' do
      it_behaves_like 'scalar JSON unsupported_surface', '"not-a-document"'
    end
  end

  describe 'URL identity cost (non-wall-clock regression guard)' do
    let(:body) { File.read('spec/fixtures/news_front_page.html') }

    let(:counts) { Hash.new(0) }

    before do
      allow(Addressable::URI).to receive(:parse).and_wrap_original do |method, *args|
        method.call(*args).tap do |uri|
          allow(uri).to receive(:normalize).and_wrap_original do |m|
            counts[:normalize] += 1
            m.call
          end
        end
      end
      allow(Html2rss::AutoSource::Cleanup).to receive(:call).and_wrap_original do |method, *args, **kwargs|
        counts[:cleanup] += 1
        method.call(*args, **kwargs)
      end
    end

    it 'normalizes each URL once and reuses one Cleanup result', :aggregate_failures do
      expect(auto_source.articles.size).to eq(25)
      expect(counts[:cleanup]).to eq(1)
      expect(counts[:normalize]).to be <= 160 # measured: 139
    end

    it 'keeps drop tallies stable', :aggregate_failures do
      auto_source.articles

      # The fixture's sister-site rail links to example.net (different_domain); one compact
      # story carries a two-word title (low_word_count).
      expect(auto_source.admission_drops)
        .to eq('different_domain' => 10, 'low_word_count' => 1)
    end
  end

  describe 'document base URL' do
    let(:url) { Html2rss::Url.from_absolute('https://example.com/en/list/') }
    let(:body) do
      <<~HTML
        <html><head><base href="#{base}"></head><body>
          <article><h2>A story that has a proper headline</h2>
            <p>Some teaser text that gives the story a body worth reading.</p>
            <a href="stories/one">Read more</a></article>
          <article><h2>Another story with a proper headline</h2>
            <p>More teaser text that gives the story a body worth reading.</p>
            <a href="stories/two">Read more</a></article>
        </body></html>
      HTML
    end

    context 'when the page declares <base href="/">' do
      let(:base) { '/' }

      it 'resolves article links against the base', :aggregate_failures do
        expect(auto_source.articles.map { _1.url.to_s })
          .to contain_exactly('https://example.com/stories/one', 'https://example.com/stories/two')
        expect(response.url.to_s).to eq('https://example.com/en/list/')
      end
    end

    context 'when the base is not http(s)' do
      let(:base) { 'javascript:void(0)' }

      it 'resolves article links against the page URL' do
        expect(auto_source.articles.map { _1.url.to_s })
          .to contain_exactly('https://example.com/en/list/stories/one', 'https://example.com/en/list/stories/two')
      end
    end

    context 'when the base points at another host' do
      let(:base) { 'https://other.example/' }

      it 'drops the cross-host item links like any cross-origin item (Cleanup keeps the page origin)' do
        expect(auto_source.articles.map { _1.url.to_s }).to be_empty
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
