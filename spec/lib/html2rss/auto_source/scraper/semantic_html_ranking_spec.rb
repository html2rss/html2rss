# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://example.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/multi_link_block.html')) }
    let(:articles) { new.each.to_a }
    let(:articles_by_url) do
      articles.to_h { |article| [article.url.to_s, article] }
    end
    let(:excluded_urls) do
      %w[
        https://example.com/category/news
        https://example.com/article/1#comments
        https://social.example/share?url=...
        https://example.com/about
        https://example.com/contact
        https://example.com/newsletter/signup
        https://example.com/gallery/3
        https://example.com/author/jane
        https://example.com/newsletter/4
      ]
    end

    it 'prefers the intended content links', :aggregate_failures do
      expect(articles_by_url.fetch('https://example.com/article/1').title).to eq('Main Article Title')
      expect(articles_by_url.fetch('https://example.com/article/3').title).to eq('Correct Title Link')
      expect(articles_by_url.fetch('https://example.com/article/4').title).to eq('Actual Article Text')
    end

    it 'suppresses utility and duplicate link variants' do
      expect(articles_by_url.keys).to contain_exactly(
        'https://example.com/article/1',
        'https://example.com/article/3',
        'https://example.com/article/4'
      )
    end

    it 'drops non-content links from noisy blocks' do
      expect(articles_by_url).not_to include(*excluded_urls)
    end
  end

  describe 'chrome suppression' do
    subject(:articles_by_url) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.to_h { |article| [article.url.to_s, article] }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html>
          <body>
            <section class="newsroom-list">
              <nav class="section-nav">
                <a href="/news">View all news</a>
                <a href="/recommended">Recommended for you</a>
              </nav>
              <article>
                <h2><a href="/news/launch-update">Launch update</a></h2>
                <p>Release notes and product changes.</p>
              </article>
            </section>
          </body>
        </html>
      HTML
    end

    it 'keeps content links while excluding common nav chrome' do
      expect(articles_by_url.keys).to contain_exactly('https://example.com/news/launch-update')
    end
  end

  describe 'post-level ranking and contamination control' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: base_url)
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:base_url) { 'https://example.com' }

    shared_examples 'top-5 prefers post-like entries' do |label|
      it "reduces nav/taxonomy contamination in top-5 for #{label}", :aggregate_failures do
        top_five = urls.first(5)

        expect(top_five).to include(*expected_story_urls)
        expect(top_five & suppressed_noise_urls).to be_empty
        expect(top_five.uniq).to eq(top_five)
      end
    end

    context 'with a brand newsroom page' do
      let(:base_url) { 'https://newsroom.example.com' }
      let(:parsed_body) do
        Nokogiri::HTML.parse(<<~HTML)
          <html><body>
            <section>
              <nav>
                <a href="/newsroom/view-all">View all</a>
                <a href="/category/company-news">Company News</a>
              </nav>
              <article><h2><a href="/news/2026/02/launch-alpha">Example launches alpha</a></h2><p>Detailed update text for users and creators.</p></article>
              <article><h2><a href="/news/2026/01/platform-improvements">Platform improvements for podcasts</a></h2><time datetime="2026-01-11"></time></article>
              <article><h2><a href="/news/2025/12/artist-tools">New artist tools</a></h2><p>Expanded publishing controls and analytics this week.</p></article>
            </section>
          </body></html>
        HTML
      end
      let(:expected_story_urls) do
        %w[
          https://newsroom.example.com/news/2026/01/platform-improvements
          https://newsroom.example.com/news/2026/02/launch-alpha
          https://newsroom.example.com/news/2025/12/artist-tools
        ]
      end
      let(:suppressed_noise_urls) do
        %w[
          https://newsroom.example.com/newsroom/view-all
          https://newsroom.example.com/category/company-news
        ]
      end

      it_behaves_like 'top-5 prefers post-like entries', 'brand newsroom'

      it 'keeps expected top ordering/composition for the brand newsroom', :aggregate_failures do
        expect(urls.first(3)).to eq(expected_story_urls)
        expect(urls.first(3).uniq).to eq(expected_story_urls)
      end
    end

    context 'with a mixed startup, course and property listing' do
      let(:base_url) { 'https://example.com' }
      let(:parsed_body) do
        Nokogiri::HTML.parse(<<~HTML)
          <html><body>
            <section>
              <article><h2><a href="/posts/lumen-startup-funding-2026">Lumen startup funding trends</a></h2><p>Longer description paragraph with material context.</p></article>
              <article><h2><a href="/stories/orbit-ai-certificates">Orbit AI certificates update</a></h2><time datetime="2026-03-01"></time></article>
              <article><h2><a href="/news/maple-market-outlook">Maple market outlook</a></h2><p>Weekly housing-market report and metrics.</p></article>
              <article><h2><a href="/topics/real-estate">Real Estate</a></h2></article>
              <article><h2><a href="/newsletter/signup">Subscribe</a></h2></article>
              <article><h2><a href="/comments/feed">Comments feed</a></h2></article>
            </section>
          </body></html>
        HTML
      end
      let(:expected_story_urls) do
        %w[
          https://example.com/stories/orbit-ai-certificates
          https://example.com/posts/lumen-startup-funding-2026
          https://example.com/news/maple-market-outlook
        ]
      end
      let(:suppressed_noise_urls) do
        %w[
          https://example.com/topics/real-estate
          https://example.com/newsletter/signup
          https://example.com/comments/feed
        ]
      end

      it_behaves_like 'top-5 prefers post-like entries', 'mixed listing'

      it 'keeps expected top ordering/composition for mixed listing', :aggregate_failures do
        expect(urls.first(3)).to eq(expected_story_urls)
        expect(urls.first(3).uniq).to eq(expected_story_urls)
      end
    end
  end

  describe 'non-regression baseline (product newsroom)' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://www.example.net')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/news/model-platform-update">Model platform update</a></h2>
              <p>Model updates, safety improvements, and API changes.</p>
              <time datetime="2026-03-25"></time>
            </article>
            <article>
              <h2><a href="/news/research-system-card">Research system card</a></h2>
              <p>Evaluation details and deployment considerations.</p>
            </article>
            <article>
              <h2><a href="/news/enterprise-rollout">Enterprise rollout</a></h2>
              <p>Availability expansion and admin controls.</p>
            </article>
            <nav><a href="/subscribe">Subscribe</a></nav>
          </section>
        </body></html>
      HTML
    end

    let(:expected_top_urls) do
      [
        'https://www.example.net/news/model-platform-update',
        'https://www.example.net/news/research-system-card',
        'https://www.example.net/news/enterprise-rollout'
      ]
    end

    it 'keeps known-good story links ahead of chrome', :aggregate_failures do
      expect(urls.uniq.first(3)).to eq(expected_top_urls)
      expect(urls).not_to include('https://www.example.net/subscribe')
    end
  end

  describe 'regression: short recommended headline with article signals' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/news/recommended-reading">Recommended reading</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Roundup with analysis and release context for this week.</p>
            </article>
            <nav>
              <a href="/recommended">Recommended for you</a>
            </nav>
          </section>
        </body></html>
      HTML
    end

    it 'keeps the legitimate post and suppresses nav chrome', :aggregate_failures do
      expect(urls).to include('https://example.com/news/recommended-reading')
      expect(urls).not_to include('https://example.com/recommended')
    end
  end

  describe 'regression: short utility headline with strong article signals' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/newsletters/weekly-market-notes">Newsletter: Weekly market notes</a></h2>
            </article>
            <article>
              <h2><a href="/stories/subscribe-for-launch-coverage">Subscribe for launch coverage</a></h2>
              <p>Field reporting, launch details, and follow-up interviews from the team.</p>
            </article>
            <nav>
              <a href="/newsletter/signup">Newsletter</a>
              <a href="/subscribe">Subscribe</a>
            </nav>
          </section>
        </body></html>
      HTML
    end

    it 'keeps legitimate article entries with sparse metadata and suppresses utility chrome', :aggregate_failures do
      expect(urls).to include('https://example.com/newsletters/weekly-market-notes')
      expect(urls).to include('https://example.com/stories/subscribe-for-launch-coverage')
      expect(urls).not_to include('https://example.com/newsletter/signup')
      expect(urls).not_to include('https://example.com/subscribe')
      expect(urls.uniq).to eq(urls)
    end
  end

  describe 'regression: publish marker counts as an article signal' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/briefing">Recommended briefing</a></h2>
              <time datetime="2026-03-28"></time>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'keeps a real post when the publish marker is a Nokogiri node' do
      expect(urls).to include('https://example.com/briefing')
    end
  end

  describe 'regression: deep section permalinks with post-like suffixes' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/category/company/platform-launch-notes-for-teams">Platform launch notes for teams</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Rollout details, migration notes, and operator guidance.</p>
            </article>
            <article>
              <h2><a href="/privacy/api-announcement-for-enterprise-admins">API announcement for enterprise admins</a></h2>
              <time datetime="2026-03-27"></time>
              <p>Important product update with support timelines and release notes.</p>
            </article>
            <article>
              <h2><a href="/newsroom/2026/platform-launch-notes">Newsroom platform launch notes</a></h2>
              <time datetime="2026-03-26"></time>
              <p>Editorial update from the newsroom with rollout detail and operator context.</p>
            </article>
            <article>
              <h2><a href="/press/2026/api-announcement-for-enterprise-admins">Press API announcement for enterprise admins</a></h2>
              <time datetime="2026-03-25"></time>
              <p>Press release with support timelines and release detail.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'keeps editorial deep routes and filters category/privacy routes', :aggregate_failures do
      expect(urls).to include('https://example.com/newsroom/2026/platform-launch-notes')
      expect(urls).to include('https://example.com/press/2026/api-announcement-for-enterprise-admins')
      expect(urls).not_to include('https://example.com/category/company/platform-launch-notes-for-teams')
      expect(urls).not_to include('https://example.com/privacy/api-announcement-for-enterprise-admins')
    end
  end

  describe 'regression: deep taxonomy and account routes stay conservative' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/topics/security/cloud">Cloud</a></h2>
              <p>Nested taxonomy page for browsing related security topics.</p>
            </article>
            <article>
              <h2><a href="/topics/security/cloud-security-updates">Cloud security updates</a></h2>
              <p>Another nested taxonomy route with a long suffix but no independent post context.</p>
            </article>
            <article>
              <h2><a href="/account/settings/security-notifications">Security notifications</a></h2>
              <p>Account settings route with a long utility tail.</p>
            </article>
            <article>
              <h2><a href="/news/platform-hardening-update">Platform hardening update</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Legitimate post entry retained as the content result.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'filters deep taxonomy and account/settings routes unless they carry trusted post context',
       :aggregate_failures do
      expect(urls).to include('https://example.com/news/platform-hardening-update')
      expect(urls).not_to include('https://example.com/topics/security/cloud')
      expect(urls).not_to include('https://example.com/topics/security/cloud-security-updates')
      expect(urls).not_to include('https://example.com/account/settings/security-notifications')
    end
  end

  describe 'regression: bare year segments do not make utility routes content' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/archive/2024">2024 archive</a></h2>
              <p>Browse everything from 2024.</p>
            </article>
            <article>
              <h2><a href="/author/2024">Author archive</a></h2>
              <p>Browse posts by one author.</p>
            </article>
            <article>
              <h2><a href="/search/2024">Search results 2024</a></h2>
              <p>Saved search result page.</p>
            </article>
            <article>
              <h2><a href="/news/2024/platform-launch-notes">Platform launch notes</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Release notes and rollout details for the platform launch.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'keeps dated permalinks and filters dated utility routes', :aggregate_failures do
      expect(urls).to include('https://example.com/news/2024/platform-launch-notes')
      expect(urls).not_to include('https://example.com/archive/2024')
      expect(urls).not_to include('https://example.com/author/2024')
      expect(urls).not_to include('https://example.com/search/2024')
    end
  end

  describe 'regression: vanity CTA heading leak' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/join">Subscribe</a></h2>
              <p>Membership offer and account benefits.</p>
            </article>
            <article>
              <h2><a href="/news/launch-update">Launch update</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Release notes and rollout guidance for the platform update.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'filters utility CTA headings on vanity routes even when they are heading anchors', :aggregate_failures do
      expect(urls).to contain_exactly('https://example.com/news/launch-update')
    end
  end

  describe 'ordering and deduplication' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="list">
            <div class="card compact">
              <h2><a href="/news/story-a">Story A</a></h2>
            </div>
            <article>
              <h2><a href="/news/story-a">Story A</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Useful context paragraph appears here for readers this week.</p>
            </article>
            <article>
              <h2><a href="/news/story-b">Story B</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Useful context paragraph appears here for readers this week.</p>
            </article>
            <article>
              <h2><a href="/news/story-c-with-context">Story C with context</a></h2>
              <time datetime="2026-03-29"></time>
              <p>Later card carries stronger post signals and should outrank earlier shallow entries.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    let(:expected_first_three_urls) do
      [
        'https://example.com/news/story-c-with-context',
        'https://example.com/news/story-a',
        'https://example.com/news/story-b'
      ]
    end

    it 'orders by final score before DOM position and keeps destination URLs unique', :aggregate_failures do
      expect(urls.first(3)).to eq(expected_first_three_urls)
      expect(urls.uniq).to eq(urls)
    end
  end

  describe 'regression: same-url dedupe keeps richer later duplicate' do
    subject(:articles) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="list">
            <div class="card compact">
              <h2><a href="/news/story-a">Story A</a></h2>
            </div>
            <article>
              <h2><a href="/news/story-a">Story A</a></h2>
              <time datetime="2026-03-28T08:30:00Z"></time>
              <p>Useful context paragraph appears here for readers this week.</p>
            </article>
            <article>
              <h2><a href="/news/story-b">Story B</a></h2>
              <time datetime="2026-03-28T09:00:00Z"></time>
              <p>Second story keeps the ordering and uniqueness checks intact.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    let(:urls) { articles.map { |article| article.url.to_s } }
    let(:story_a) { articles.find { |article| article.url.to_s == 'https://example.com/news/story-a' } }
    let(:expected_first_two_urls) do
      [
        'https://example.com/news/story-a',
        'https://example.com/news/story-b'
      ]
    end

    it 'retains the richer candidate for the shared destination URL', :aggregate_failures do
      expect(urls.first(2)).to eq(expected_first_two_urls)
      expect(urls.uniq).to eq(urls)
      expect(story_a.published_at&.iso8601).to eq('2026-03-28T08:30:00+00:00')
      expect(story_a.description).to include('Useful context paragraph')
    end
  end

  describe 'dedupe comparator precedence' do
    let(:deduplicator) { described_class::EntryDeduplicator.new('https://example.com') }

    let(:root_node) { Html2rss::SST::Node.build(name: :article) }
    let(:primary_link) do
      Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/news/story'))
    end
    let(:base_article) do
      Html2rss::Article.new(
        title: 'Story',
        url: Html2rss::Url.from_relative('/news/story', 'https://example.com'),
        image: nil,
        description: 'Short summary',
        id: 'story',
        published_at: nil,
        categories: [],
        enclosures: []
      )
    end
    let(:entry_builder) do
      lambda do |quality_score:, junk_score:, final_score:, position:, article:|
        segment = Html2rss::AutoSource::Segment.build(
          root_node:,
          primary_link:,
          strategy: :semantic,
          position:
        )
        ranked = Html2rss::Scoring::RankedSegment.new(
          segment:,
          score: Html2rss::Scoring::Score.new(
            composite: final_score.to_f,
            quality: quality_score.to_f,
            junk: junk_score.to_f,
            breakdown: Html2rss::Scoring::Score::EMPTY_BREAKDOWN
          )
        )
        allow(deduplicator).to receive(:article_for).with(ranked).and_return(article)
        ranked
      end
    end

    it 'prefers higher final_score over richer payload' do # rubocop:disable RSpec/ExampleLength
      higher_score = entry_builder.call(
        quality_score: 80,
        junk_score: 10,
        final_score: 70,
        position: 1,
        article: base_article
      )
      richer_payload = entry_builder.call(
        quality_score: 65,
        junk_score: 10,
        final_score: 55,
        position: 0,
        article: Html2rss::Article.new(
          title: 'Story',
          url: Html2rss::Url.from_relative('/news/story', 'https://example.com'),
          image: 'https://example.com/story.png',
          description: 'Much longer summary with additional supporting context for comparison',
          id: 'story',
          categories: %w[news launch],
          enclosures: [{ url: Html2rss::Url.from_relative('/audio.mp3', 'https://example.com') }]
        )
      )

      expect(deduplicator.stronger_entry?(higher_score, richer_payload)).to be(true)
    end

    it 'prefers higher quality_score when final_score is tied' do # rubocop:disable RSpec/ExampleLength
      higher_quality = entry_builder.call(
        quality_score: 80,
        junk_score: 20,
        final_score: 60,
        position: 1,
        article: base_article
      )
      richer_payload = entry_builder.call(
        quality_score: 70,
        junk_score: 10,
        final_score: 60,
        position: 0,
        article: Html2rss::Article.new(
          title: 'Story',
          url: Html2rss::Url.from_relative('/news/story', 'https://example.com'),
          image: 'https://example.com/story.png',
          description: 'Longer summary with more details for payload richness',
          id: 'story',
          categories: %w[news launch]
        )
      )

      expect(deduplicator.stronger_entry?(higher_quality, richer_payload)).to be(true)
    end

    it 'prefers richer payload when final_score and quality_score are tied' do # rubocop:disable RSpec/ExampleLength
      leaner = entry_builder.call(
        quality_score: 75,
        junk_score: 10,
        final_score: 65,
        position: 1,
        article: base_article
      )
      richer = entry_builder.call(
        quality_score: 75,
        junk_score: 10,
        final_score: 65,
        position: 2,
        article: Html2rss::Article.new(
          title: 'Story',
          url: Html2rss::Url.from_relative('/news/story', 'https://example.com'),
          image: 'https://example.com/story.png',
          description: 'Longer summary with materially richer extraction data for the duplicate',
          id: 'story',
          published_at: Time.utc(2026, 3, 28),
          categories: %w[news launch],
          enclosures: [{ url: Html2rss::Url.from_relative('/audio.mp3', 'https://example.com') }]
        )
      )

      expect(deduplicator.stronger_entry?(richer, leaner)).to be(true)
    end

    it 'falls back to DOM position on an exact tie' do # rubocop:disable RSpec/ExampleLength
      earlier = entry_builder.call(
        quality_score: 75,
        junk_score: 10,
        final_score: 65,
        position: 0,
        article: base_article
      )
      later = entry_builder.call(
        quality_score: 75,
        junk_score: 10,
        final_score: 65,
        position: 1,
        article: base_article
      )

      expect(deduplicator.stronger_entry?(earlier, later)).to be(true)
    end
  end

  describe 'regression: exact ties fall back to real DOM order' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    let(:expected_first_two_urls) do
      [
        'https://example.com/news/first-story',
        'https://example.com/news/second-story'
      ]
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="list">
            <div id="first">
              <h2><a href="/news/first-story">First story headline</a></h2>
              <p>Supporting text gives this card descriptive context for readers.</p>
            </div>
            <article id="second">
              <h2><a href="/news/second-story">Second story headline</a></h2>
            </article>
          </section>
        </body></html>
      HTML
    end

    it 'uses document order instead of selector bucket order on an exact score tie' do
      expect(urls.first(2)).to eq(expected_first_two_urls)
    end
  end

  describe 'dedupe perf shape' do
    subject(:deduplicator) { described_class::EntryDeduplicator.new('https://example.com') }

    let(:entries) do
      Array.new(4) do |index|
        root = Html2rss::SST::Node.build(name: :article, attrs: Html2rss::SST::Attrs.build(id: "s#{index}"))
        link = Html2rss::SST::Node.build(
          name: :a,
          attrs: Html2rss::SST::Attrs.build(href: "/news/story-#{index}"),
          own_text: "Story #{index}"
        )
        segment = Html2rss::AutoSource::Segment.build(
          root_node: root,
          primary_link: link,
          strategy: :semantic,
          position: index
        )
        Html2rss::Scoring::RankedSegment.new(
          segment:,
          score: Html2rss::Scoring::Score.new(
            composite: 60.0,
            quality: 70.0,
            junk: 10.0,
            breakdown: Html2rss::Scoring::Score::EMPTY_BREAKDOWN
          )
        )
      end
    end

    it 'skips nested-container checks for single-entry destination groups', :aggregate_failures do
      deduplicated = nil

      expect do
        deduplicated = deduplicator.call(entries)
      end.not_to raise_error

      expect(deduplicated.size).to eq(4)
    end
  end

  describe 'lazy article extraction verification' do
    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="list">
            <article class="first">
              <h2><a href="/news/story-a">Story A</a></h2>
            </article>
            <article class="second">
              <h2><a href="/news/story-a">Story A</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Much longer description with enough words to satisfy the descriptive context signal without a tie.</p>
            </article>
          </section>
        </body></html>
      HTML
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'only calls Html::SstArticleExtractor on the final winners', :aggregate_failures do
      article = Html2rss::Article.new(
        title: 'Story A',
        url: Html2rss::Url.from_relative('/news/story-a', 'https://example.com'),
        image: nil,
        description: 'Much longer description with enough words to satisfy context without a tie.',
        id: 'story-a',
        published_at: Time.utc(2026, 3, 28),
        categories: [],
        enclosures: [],
        scraper: described_class
      )
      allow(Html2rss::Html::SstArticleExtractor).to receive(:call).and_return(article)

      scraper = described_class.new(parsed_body, url: 'https://example.com')
      results = scraper.each.to_a

      expect(results.size).to eq(1)
      expect(Html2rss::Html::SstArticleExtractor).to have_received(:call).once
    end
  end

  describe 'CSS class and ID scoring' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article.url.to_s }
    end

    context 'when ordering containers with content vs junk classes' do
      let(:parsed_body) do
        Nokogiri::HTML.parse(<<~HTML)
          <html><body>
            <div class="sidebar-widget" id="footer-menu">
              <h2><a href="/news/story-b">Story B in sidebar</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Description text descriptive context word count limit here.</p>
            </div>
            <div class="blog-teaser" id="featured-story">
              <h2><a href="/news/story-a">Story A in teaser</a></h2>
              <time datetime="2026-03-28"></time>
              <p>Description text descriptive context word count limit here.</p>
            </div>
          </body></html>
        HTML
      end

      it 'ranks the content-like container before the junk-like container' do
        expected = [
          'https://example.com/news/story-a',
          'https://example.com/news/story-b'
        ]
        expect(urls).to eq(expected)
      end
    end
  end

  describe '.group_bonus' do
    it 'grows by a fixed amount per doubling of the group', :aggregate_failures do
      expect(described_class.group_bonus(1)).to eq(0.0)
      expect(described_class.group_bonus(2)).to eq(3.0)
      expect(described_class.group_bonus(16)).to eq(12.0)
    end

    it 'is bounded', :aggregate_failures do
      expect(described_class.group_bonus(32)).to eq(15.0)
      expect(described_class.group_bonus(4096)).to eq(15.0)
    end
  end

  describe 'repeated-card group ranking' do
    subject(:urls) do
      page = Nokogiri::HTML.parse(File.read('spec/fixtures/auto_source/corpus/nested_card_grid_ranking.html'))
      described_class.new(page, url: 'https://example.com').each.map { |article| article.url.to_s }
    end

    let(:grid_urls) { urls.grep(%r{/local/}) }

    it 'reads every nested grid card as an item', :aggregate_failures do
      expect(grid_urls.size).to eq(25)
      expect(grid_urls).to all(match(%r{\Ahttps://example\.com/local/2026/11/[a-z-]+/\z}))
    end

    it 'ranks the grid before the regional module and the service rail', :aggregate_failures do
      expect(urls.first(25)).to eq(grid_urls)
      expect(urls.drop(25).grep(%r{/(regional|service)/}).size).to eq(12)
    end

    it 'keeps the smaller groups' do
      expect(urls.size).to eq(37)
    end

    context 'when a huge group of plain cards meets a few markedly more prominent articles' do
      subject(:urls) do
        page = Nokogiri::HTML.parse(<<~HTML)
          <html><body><main>
            <section>#{Array.new(200) { plain_card.call(_1) }.join}</section>
            <section>#{Array.new(3) { article_card.call(_1) }.join}</section>
          </main></body></html>
        HTML
        described_class.new(page, url: 'https://example.com').each.map { |article| article.url.to_s }
      end

      let(:plain_card) do
        lambda do |index|
          %(<div class="cell"><h3><a href="/local/2026/#{index}/story/">Local story #{index} today</a></h3></div>)
        end
      end
      let(:article_card) do
        lambda do |index|
          <<~HTML
            <article class="lead"><h3><a href="/regional/2026/#{index}/story/">Regional story #{index} today</a></h3>
            <p>Officials expect a smooth rollout of the change.</p><time datetime="2026-11-12T10:00">10:00</time></article>
          HTML
        end
      end

      it 'keeps the bonus bounded, so the articles still lead' do
        expect(urls.first(3).grep(%r{/regional/}).size).to eq(3)
      end
    end

    context 'when the groups together exceed the item cap' do
      subject(:urls) do
        page = Nokogiri::HTML.parse(<<~HTML)
          <html><body><main>
            <section>#{Array.new(5) { prominent_card.call(_1) }.join}</section>
            <section>#{Array.new(120) { plain_card.call(_1) }.join}</section>
          </main></body></html>
        HTML
        described_class.new(page, url: 'https://example.com').each.map { |article| article.url.to_s }
      end

      let(:prominent_card) do
        lambda do |index|
          %(<div class="rail"><h3><a href="/regional/2026/#{index}/story/">Regional story #{index} today</a></h3></div>)
        end
      end
      let(:plain_card) do
        lambda do |index|
          %(<div class="cell"><h3><a href="/local/2026/#{index}/story/">Local story #{index} today</a></h3></div>)
        end
      end

      it 'caps after ranking, so the largest group fills the cap', :aggregate_failures do
        expect(urls.size).to be <= described_class::TOP_K
        expect(urls.grep(%r{/regional/}).size).to be < 5
      end
    end
  end
end
