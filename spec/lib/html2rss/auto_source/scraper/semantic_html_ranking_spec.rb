# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/multi_link_block.html')) }
    let(:articles) { new.each.to_a }
    let(:articles_by_url) do
      articles.to_h { |article| [article[:url].to_s, article] }
    end
    let(:excluded_urls) do
      %w[
        https://page.com/category/news
        https://page.com/article/1#comments
        https://twitter.com/share?url=...
        https://page.com/about
        https://page.com/contact
        https://page.com/newsletter/signup
        https://page.com/gallery/3
        https://page.com/author/jane
        https://page.com/newsletter/4
      ]
    end

    it 'prefers the intended content links', :aggregate_failures do
      expect(articles_by_url.fetch('https://page.com/article/1')[:title]).to eq('Main Article Title')
      expect(articles_by_url.fetch('https://page.com/article/3')[:title]).to eq('Correct Title Link')
      expect(articles_by_url.fetch('https://page.com/article/4')[:title]).to eq('Actual Article Text')
    end

    it 'suppresses utility and duplicate link variants' do
      expect(articles_by_url.keys).to contain_exactly(
        'https://page.com/article/1',
        'https://page.com/article/3',
        'https://page.com/article/4'
      )
    end

    it 'drops non-content links from noisy blocks' do
      expect(articles_by_url).not_to include(*excluded_urls)
    end
  end

  describe 'chrome suppression' do
    subject(:articles_by_url) do
      scraper = described_class.new(parsed_body, url: 'https://page.com')
      scraper.each.to_a.to_h { |article| [article[:url].to_s, article] }
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
      expect(articles_by_url.keys).to contain_exactly('https://page.com/news/launch-update')
    end
  end

  describe 'post-level ranking and contamination control' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: base_url)
      scraper.each.to_a.map { |article| article[:url].to_s }
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

    context 'with a spotify-like newsroom page' do
      let(:base_url) { 'https://newsroom.spotify.com' }
      let(:parsed_body) do
        Nokogiri::HTML.parse(<<~HTML)
          <html><body>
            <section>
              <nav>
                <a href="/newsroom/view-all">View all</a>
                <a href="/category/company-news">Company News</a>
              </nav>
              <article><h2><a href="/news/2026/02/launch-alpha">Spotify launches alpha</a></h2><p>Detailed update text for users and creators.</p></article>
              <article><h2><a href="/news/2026/01/platform-improvements">Platform improvements for podcasts</a></h2><time datetime="2026-01-11"></time></article>
              <article><h2><a href="/news/2025/12/artist-tools">New artist tools</a></h2><p>Expanded publishing controls and analytics this week.</p></article>
            </section>
          </body></html>
        HTML
      end
      let(:expected_story_urls) do
        %w[
          https://newsroom.spotify.com/news/2026/01/platform-improvements
          https://newsroom.spotify.com/news/2026/02/launch-alpha
          https://newsroom.spotify.com/news/2025/12/artist-tools
        ]
      end
      let(:suppressed_noise_urls) do
        %w[
          https://newsroom.spotify.com/newsroom/view-all
          https://newsroom.spotify.com/category/company-news
        ]
      end

      it_behaves_like 'top-5 prefers post-like entries', 'Spotify'

      it 'keeps expected top ordering/composition for Spotify', :aggregate_failures do
        expect(urls.first(3)).to eq(expected_story_urls)
        expect(urls.first(3).uniq).to eq(expected_story_urls)
      end
    end

    context 'with a yc/coursera/zillow-like listing mix' do
      let(:base_url) { 'https://example.com' }
      let(:parsed_body) do
        Nokogiri::HTML.parse(<<~HTML)
          <html><body>
            <section>
              <article><h2><a href="/posts/yc-startup-funding-2026">YC startup funding trends</a></h2><p>Longer description paragraph with material context.</p></article>
              <article><h2><a href="/stories/coursera-ai-certificates">Coursera AI certificates update</a></h2><time datetime="2026-03-01"></time></article>
              <article><h2><a href="/news/zillow-market-outlook">Zillow market outlook</a></h2><p>Weekly housing-market report and metrics.</p></article>
              <article><h2><a href="/topics/real-estate">Real Estate</a></h2></article>
              <article><h2><a href="/newsletter/signup">Subscribe</a></h2></article>
              <article><h2><a href="/comments/feed">Comments feed</a></h2></article>
            </section>
          </body></html>
        HTML
      end
      let(:expected_story_urls) do
        %w[
          https://example.com/stories/coursera-ai-certificates
          https://example.com/posts/yc-startup-funding-2026
          https://example.com/news/zillow-market-outlook
        ]
      end
      let(:suppressed_noise_urls) do
        %w[
          https://example.com/topics/real-estate
          https://example.com/newsletter/signup
          https://example.com/comments/feed
        ]
      end

      it_behaves_like 'top-5 prefers post-like entries', 'YC/Coursera/Zillow'

      it 'keeps expected top ordering/composition for YC/Coursera/Zillow', :aggregate_failures do
        expect(urls.first(3)).to eq(expected_story_urls)
        expect(urls.first(3).uniq).to eq(expected_story_urls)
      end
    end
  end

  describe 'non-regression baseline (Anthropic-like)' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://www.anthropic.com')
      scraper.each.to_a.map { |article| article[:url].to_s }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="updates">
            <article>
              <h2><a href="/news/claude-platform-update">Claude platform update</a></h2>
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
        'https://www.anthropic.com/news/claude-platform-update',
        'https://www.anthropic.com/news/research-system-card',
        'https://www.anthropic.com/news/enterprise-rollout'
      ]
    end

    it 'keeps known-good story links ahead of chrome', :aggregate_failures do
      expect(urls.uniq.first(3)).to eq(expected_top_urls)
      expect(urls).not_to include('https://www.anthropic.com/subscribe')
    end
  end

  describe 'regression: short recommended headline with article signals' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article[:url].to_s }
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
      scraper.each.to_a.map { |article| article[:url].to_s }
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

  describe 'regression: deep section permalinks with post-like suffixes' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article[:url].to_s }
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
          </section>
        </body></html>
      HTML
    end

    it 'keeps ambiguous deep utility-segment routes in extraction instead of hard-dropping them', :aggregate_failures do
      expect(urls).to include('https://example.com/category/company/platform-launch-notes-for-teams')
      expect(urls).to include('https://example.com/privacy/api-announcement-for-enterprise-admins')
    end
  end

  describe 'regression: deep taxonomy and account routes stay conservative' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article[:url].to_s }
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

  describe 'regression: vanity CTA heading leak' do
    subject(:urls) do
      scraper = described_class.new(parsed_body, url: 'https://example.com')
      scraper.each.to_a.map { |article| article[:url].to_s }
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
      scraper.each.to_a.map { |article| article[:url].to_s }
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

    let(:urls) { articles.map { |article| article[:url].to_s } }
    let(:story_a) { articles.find { |article| article[:url].to_s == 'https://example.com/news/story-a' } }
    let(:expected_first_two_urls) do
      [
        'https://example.com/news/story-a',
        'https://example.com/news/story-b'
      ]
    end

    it 'retains the richer candidate for the shared destination URL', :aggregate_failures do
      expect(urls.first(2)).to eq(expected_first_two_urls)
      expect(urls.uniq).to eq(urls)
      expect(story_a[:published_at]&.iso8601).to eq('2026-03-28T08:30:00+00:00')
      expect(story_a[:description]).to include('Useful context paragraph')
    end
  end

  describe 'dedupe comparator precedence' do
    subject(:scraper) { described_class.new(Nokogiri::HTML.parse('<html><body></body></html>'), url: 'https://example.com') }

    let(:container) { Nokogiri::HTML.fragment('<article><a href="/news/story">Story</a></article>').at_css('article') }
    let(:anchor) { container.at_css('a') }
    let(:base_article) do
      {
        title: 'Story',
        url: Html2rss::Url.from_relative('/news/story', 'https://example.com'),
        image: nil,
        description: 'Short summary',
        published_at: nil,
        categories: [],
        enclosures: []
      }
    end
    let(:entry_builder) do
      lambda do |quality_score:, junk_score:, final_score:, position:, article:|
        described_class::Entry.new(
          container:,
          selected_anchor: anchor,
          destination_facts: nil,
          quality_score:,
          junk_score:,
          final_score:,
          position:,
          article:
        )
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
        article: base_article.merge(
          image: 'https://example.com/story.png',
          description: 'Much longer summary with additional supporting context for comparison',
          categories: %w[news launch],
          enclosures: [{ url: 'https://example.com/audio.mp3' }]
        )
      )

      expect(scraper.instance_eval { stronger_entry?(higher_score, richer_payload) }).to be(true)
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
        article: base_article.merge(
          image: 'https://example.com/story.png',
          description: 'Longer summary with more details for payload richness',
          categories: %w[news launch]
        )
      )

      expect(scraper.instance_eval { stronger_entry?(higher_quality, richer_payload) }).to be(true)
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
        article: base_article.merge(
          image: 'https://example.com/story.png',
          description: 'Longer summary with materially richer extraction data for the duplicate',
          published_at: Time.utc(2026, 3, 28),
          categories: %w[news launch],
          enclosures: [{ url: 'https://example.com/audio.mp3' }]
        )
      )

      expect(scraper.instance_eval { stronger_entry?(richer, leaner) }).to be(true)
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

      expect(scraper.instance_eval { stronger_entry?(earlier, later) }).to be(true)
    end
  end

  describe 'dedupe perf shape' do
    subject(:scraper) { described_class.new(parsed_body, url: 'https://example.com') }

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html><body>
          <section class="list">
            <article><h2><a href="/news/story-1">Story 1</a></h2><time datetime="2026-03-28"></time><p>Useful context for story one.</p></article>
            <article><h2><a href="/news/story-2">Story 2</a></h2><time datetime="2026-03-28"></time><p>Useful context for story two.</p></article>
            <article><h2><a href="/news/story-3">Story 3</a></h2><time datetime="2026-03-28"></time><p>Useful context for story three.</p></article>
            <article><h2><a href="/news/story-4">Story 4</a></h2><time datetime="2026-03-28"></time><p>Useful context for story four.</p></article>
          </section>
        </body></html>
      HTML
    end

    let(:container) do
      instance_double(Nokogiri::XML::Node).tap do |node|
        allow(node).to receive(:ancestors).and_raise('cross-group nested comparison executed')
      end
    end
    let(:entries) do
      Array.new(4) do |index|
        described_class::Entry.new(
          container:,
          selected_anchor: nil,
          destination_facts: nil,
          quality_score: 70,
          junk_score: 10,
          final_score: 60,
          position: index,
          article: {
            title: "Story #{index}",
            url: Html2rss::Url.from_relative("/news/story-#{index}", 'https://example.com'),
            image: nil,
            description: 'Short summary',
            published_at: nil,
            categories: [],
            enclosures: []
          }
        )
      end
    end

    it 'skips nested-container checks for single-entry destination groups', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      deduplicated = nil

      expect do
        deduplicated = scraper.instance_exec(entries) do |candidate_entries|
          deduplicate_by_destination(candidate_entries)
        end
      end.not_to raise_error

      expect(deduplicated.size).to eq(4)
    end
  end
end
