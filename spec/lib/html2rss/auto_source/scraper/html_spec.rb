# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Html do
  let(:html) do
    <<~HTML
      <!DOCTYPE html>
      <html>

      <head>
        <title>Sample Document</title>
      </head>

      <body>
        <h1>Main Heading</h1>
        <article>
          <h2>Article 1 Headline</h2>
          <p>
            Teaser for article 1.
            <a href="article1/">Read more</a>
          </p>
        </article>
        <article>
          <h2>Article 2 Headline</h2>
          <p>
            Teaser for article 2.
            <a href="article2/">Read more</a>
          </p>
        </article>
      </body>

      </html>
    HTML
  end
  let(:parsed_body) do
    Nokogiri::HTML(html)
  end

  let(:anchorless_html) do
    Nokogiri::HTML.parse <<~HTML
      <html><body>
        <article><h2>No Link One</h2><p>Description one.</p></article>
        <article><h2>No Link Two</h2><p>Description two.</p></article>
      </body></html>
    HTML
  end

  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:html) }
  end

  describe '.articles?(parsed_body)' do
    subject(:articles?) { described_class.articles?(parsed_body) }

    it { is_expected.to be_truthy }

    context 'when the page uses only relative story links' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <body>
              <section class="cards">
                <div class="card">
                  <h2><a href="/news/launch-update">Launch update</a></h2>
                </div>
                <div class="card">
                  <h2><a href="/news/api-rollout">API rollout</a></h2>
                </div>
              </section>
            </body>
          </html>
        HTML
      end

      it 'still detects extractable repeated content' do
        expect(articles?).to be(true)
      end
    end

    context 'when parsed_body is empty' do
      let(:parsed_body) { Nokogiri::HTML('') }

      it { is_expected.to be(false) }
    end
  end

  describe '#each' do
    subject(:articles) { described_class.new(parsed_body, url: 'http://example.com') }

    let(:first_article) do
      { title: 'Article 1 Headline',
        url: be_a(Html2rss::Url),
        image: nil,
        description: 'Teaser for article 1.',
        id: '/article1/',
        published_at: nil,
        enclosures: [] }
    end
    let(:second_article) do
      { title: 'Article 2 Headline',
        url: be_a(Html2rss::Url),
        image: nil,
        description: 'Teaser for article 2.',
        id: '/article2/',
        published_at: nil,
        enclosures: [] }
    end

    it 'yields articles' do
      expect { |b| articles.each(&b) }.to yield_control.twice
    end

    it 'contains the two articles', :aggregate_failures do
      first, last = articles.to_a

      expect(first).to have_attributes(first_article)
      expect(last).to have_attributes(second_article)
    end

    context 'when parsed_body does not wrap article in an element' do
      let(:html) do
        <<~HTML
          <!doctype html>
          <html lang="de"><meta charset="utf-8">
          <h3>Sun Oct 27 2024</h3>
          <ul>
            <li>
              <a href="?ts=deadh0rse">[Plonk]</a>
              <a href="https://www.tagesschau.de/wirtschaft/verbraucher/kosten-autos-deutsche-hersteller-100.html">Bla bla bla</a>
          </ul>
          </html>
        HTML
      end

      let(:first_article) do
        { title: '[Plonk]',
          url: be_a(Html2rss::Url),
          image: nil,
          description: nil,
          id: '/',
          published_at: nil,
          enclosures: [] }
      end

      let(:second_article) do
        {
          title: 'Bla bla bla',
          url: be_a(Html2rss::Url),
          image: nil,
          description: nil,
          id: '/wirtschaft/verbraucher/kosten-autos-deutsche-hersteller-100.html',
          published_at: nil,
          enclosures: []
        }
      end

      it 'derives the first id from the selected anchor url' do
        expect(articles.first.id).to eq('/')
      end

      it 'derives the second id from the selected anchor url' do
        expect(articles.to_a.last.id).to eq('/wirtschaft/verbraucher/kosten-autos-deutsche-hersteller-100.html')
      end

      it 'contains the first_article' do
        expect(articles.first).to have_attributes(first_article)
      end

      it 'contains the second_article' do
        expect(articles.to_a[-1]).to have_attributes(second_article)
      end
    end

    context 'when parsed_body is empty' do
      let(:parsed_body) { Nokogiri::HTML('') }

      it 'does not yield articles' do
        expect(articles.to_a).to eq([])
      end
    end

    context 'with repeated taxonomy and vanity noise' do
      let(:html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <body>
              <ul class="taxonomy-list">
                <li><a href="/topics/markets">Markets</a></li>
                <li><a href="/topics/security">Security</a></li>
                <li><a href="/topics/platform">Platform</a></li>
                <li><a href="/topics/security/cloud">Cloud</a></li>
                <li><a href="/topics/security/cloud-security-updates">Cloud security updates</a></li>
              </ul>
              <section class="cards">
                <div class="card">
                  <h2>Launch update</h2>
                  <p>Shipping details for operators and customers.</p>
                  <a href="/news/launch-update">Read more</a>
                </div>
                <div class="card">
                  <h2>API rollout</h2>
                  <p>Migration notes and support timelines.</p>
                  <a href="/news/api-rollout">Read more</a>
                </div>
                <div class="card">
                  <h2>Subscribe</h2>
                  <p>Membership plans and pricing.</p>
                  <a href="/join">Subscribe</a>
                </div>
                <div class="card">
                  <h2>Security notifications</h2>
                  <p>Account preferences and notification controls.</p>
                  <a href="/account/settings/security-notifications">Manage notifications</a>
                </div>
              </section>
            </body>
          </html>
        HTML
      end

      it 'reduces utility and taxonomy contamination in fallback extraction', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        urls = articles.to_a.map { |article| article.url.to_s }

        expect(urls).to include('http://example.com/news/launch-update')
        expect(urls).to include('http://example.com/news/api-rollout')
        expect(urls).not_to include('http://example.com/topics/markets')
        expect(urls).not_to include('http://example.com/topics/security')
        expect(urls).not_to include('http://example.com/topics/platform')
        expect(urls).not_to include('http://example.com/topics/security/cloud')
        expect(urls).not_to include('http://example.com/topics/security/cloud-security-updates')
        expect(urls).not_to include('http://example.com/account/settings/security-notifications')
        expect(urls).not_to include('http://example.com/join')
      end
    end

    context 'when a valid story link comes after chrome inside the same card' do
      let(:html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <body>
              <section class="cards">
                <div class="card">
                  <a href="/topics/platform">Platform</a>
                  <div class="story-links">
                    <a href="/news/launch-update"><img alt="Launch update" src="/launch.png"></a>
                    <h2><a href="/news/launch-update">Launch update</a></h2>
                  </div>
                  <p>Shipping details for operators and customers this week.</p>
                </div>
                <div class="card">
                  <a href="/join">Subscribe</a>
                  <div class="story-links">
                    <a href="/news/api-rollout"><img alt="API rollout" src="/api.png"></a>
                    <h2><a href="/news/api-rollout">API rollout</a></h2>
                  </div>
                  <p>Migration notes and support timelines for teams.</p>
                </div>
              </section>
            </body>
          </html>
        HTML
      end

      it 'keeps the later story link that made the container relevant', :aggregate_failures do
        urls = articles.to_a.map { |article| article.url.to_s }

        expect(urls).to include('http://example.com/news/launch-update')
        expect(urls).to include('http://example.com/news/api-rollout')
        expect(urls).not_to include('http://example.com/topics/platform')
        expect(urls).not_to include('http://example.com/join')
      end

      it 'uses the later story anchor instead of the first descendant chrome link', :aggregate_failures do
        first_article = articles.to_a.first

        expect(first_article).to have_attributes(title: 'Launch update', id: '/news/launch-update')
        expect(first_article.url.to_s).to eq('http://example.com/news/launch-update')
      end
    end

    context 'when repeated article-like cards use author and archive permalinks' do
      let(:html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <body>
              <section class="cards">
                <article class="card">
                  <h2><a href="/author/quarterly-platform-hardening-update">Quarterly platform hardening update</a></h2>
                  <p>Incident follow-up, rollout sequencing, and operator guidance for the quarter.</p>
                </article>
                <article class="card">
                  <h2><a href="/archive/launch-retrospective-notes-for-teams">Launch retrospective notes for teams</a></h2>
                  <p>Migration notes, release learnings, and detailed guidance from the team.</p>
                </article>
                <article class="card">
                  <h2><a href="/join">Subscribe</a></h2>
                  <p>Membership upsell and account benefits.</p>
                </article>
                <article class="card">
                  <h2><a href="/account/settings/security-notifications">Security notifications</a></h2>
                  <p>Account settings and notification controls.</p>
                </article>
              </section>
            </body>
          </html>
        HTML
      end

      it 'keeps ambiguous deep routes with article-like card context while filtering clear utility cards',
         :aggregate_failures do
        urls = articles.to_a.map { |article| article.url.to_s }

        expect(urls).to include('http://example.com/author/quarterly-platform-hardening-update')
        expect(urls).to include('http://example.com/archive/launch-retrospective-notes-for-teams')
        expect(urls).not_to include('http://example.com/join')
        expect(urls).not_to include('http://example.com/account/settings/security-notifications')
      end
    end
  end

  describe '.request_slots' do
    it 'reserves no request slots regardless of options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_pages: 2)).to eq(0)
    end
  end

  describe '.articles?(parsed_body)' do
    it 'returns false without a parsed body' do
      expect(described_class.articles?(nil)).to be(false)
    end
  end

  describe '#extractable?' do
    it 'is true for repeated linked cards', :aggregate_failures do
      expect(described_class.new(Nokogiri::HTML.parse(html), url: 'http://example.com')).to be_extractable
    end

    it 'is false for anchorless cards unless fallback_anchorless is requested', :aggregate_failures do
      expect(described_class.new(anchorless_html, url: 'https://page.com')).not_to be_extractable
      expect(described_class.new(anchorless_html, url: 'https://page.com', fallback_anchorless: true))
        .to be_extractable
    end
  end

  describe '#initialize' do
    it 'drops anchorless cards by default' do
      expect(described_class.new(anchorless_html, url: 'https://page.com').to_a).to eq([])
    end

    it 'resolves relative article links against the given url' do
      articles = described_class.new(Nokogiri::HTML.parse(html), url: 'https://page.example/').to_a

      expect(articles.map { _1.url.to_s }).to include('https://page.example/article1/')
    end
  end

  describe '#document' do
    it 'uses a provided SST document without a parsed body' do
      document = Html2rss::SST::Normalizer.call(Nokogiri::HTML.parse(html))

      articles = described_class.new(nil, url: 'http://example.com', document:).to_a

      expect(articles.map(&:title)).to include('Article 1 Headline')
    end

    it 'normalizes the parsed body when no document is provided' do
      articles = described_class.new(Nokogiri::HTML.parse(html), url: 'http://example.com').to_a

      expect(articles.map(&:title)).to include('Article 1 Headline')
    end
  end

  describe '#link_resolver' do
    it 'uses a provided link resolver' do
      resolver = Html2rss::Scoring::LinkResolver.new('http://example.com')
      allow(resolver).to receive(:destination_facts).and_call_original

      described_class.new(Nokogiri::HTML.parse(html), url: 'http://example.com', link_resolver: resolver).to_a

      expect(resolver).to have_received(:destination_facts).at_least(:once)
    end
  end

  describe '#articles' do
    it 'stamps extracted articles with the html scraper class', :aggregate_failures do
      articles = described_class.new(Nokogiri::HTML.parse(html), url: 'http://example.com').to_a

      expect(articles).not_to be_empty
      expect(articles.map(&:scraper).uniq).to eq([described_class])
    end

    it 'keeps anchorless cards only when fallback_anchorless is requested' do
      articles = described_class.new(anchorless_html, url: 'https://page.com', fallback_anchorless: true).to_a

      expect(articles.map(&:title)).to eq(['No Link One', 'No Link Two'])
    end
  end

  describe '#materialize' do
    it 'stamps the scraper class on fallback anchorless articles' do
      articles = described_class.new(anchorless_html, url: 'https://page.com', fallback_anchorless: true).to_a

      expect(articles.map(&:scraper).uniq).to eq([described_class])
    end
  end

  describe '#cluster_ranked' do
    it 'only supplies anchorless clusters when fallback_anchorless is requested', :aggregate_failures do
      expect(described_class.new(anchorless_html, url: 'https://page.com').to_a).to be_empty
      expect(described_class.new(anchorless_html, url: 'https://page.com', fallback_anchorless: true).to_a.size)
        .to eq(2)
    end
  end

  describe '#minimum_selector_frequency' do
    it 'drops selectors that occur less often than the configured floor' do
      articles = described_class.new(Nokogiri::HTML.parse(html), url: 'http://example.com',
                                                                 minimum_selector_frequency: 3).to_a

      expect(articles).to be_empty
    end
  end
end
