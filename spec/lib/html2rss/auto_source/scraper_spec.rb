# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'rspec'

RSpec.describe Html2rss::AutoSource::Scraper do
  it { is_expected.to be_a(Module) }
  it { expect(described_class::SCRAPERS).to be_an(Array) }

  describe '::SCRAPER_TIERS' do
    it 'starts with NativeFeed before in-page structured scrapers' do
      expect(described_class::SCRAPER_TIERS.first).to eq(
        [Html2rss::AutoSource::Scraper::NativeFeed]
      )
    end

    it 'places structured scrapers in the second tier' do
      expect(described_class::SCRAPER_TIERS[1]).to include(
        Html2rss::AutoSource::Scraper::Schema,
        Html2rss::AutoSource::Scraper::JsonState
      )
    end

    it 'ends with SemanticHtml then Html' do
      expect(described_class::SCRAPER_TIERS.last(2)).to eq(
        [[Html2rss::AutoSource::Scraper::SemanticHtml], [Html2rss::AutoSource::Scraper::Html]]
      )
    end

    it 'prefixes DOCUMENT_SCRAPERS then flattens SCRAPER_TIERS into SCRAPERS' do
      expect(described_class::SCRAPERS).to eq(
        described_class::DOCUMENT_SCRAPERS + described_class::SCRAPER_TIERS.flatten
      )
    end

    it 'registers NativeFeed for request sessions' do
      expect(described_class::REQUEST_SESSION_SCRAPERS).to include(
        Html2rss::AutoSource::Scraper::NativeFeed
      )
    end
  end

  describe 'scraper protocol' do
    described_class::SCRAPERS.each do |klass|
      describe klass.name do
        it 'declares request_slots so AutoSource can sum follow-up budget without a fallback' do
          expect(klass.request_slots({})).to be_an(Integer)
        end

        it 'declares extractable? so instance matching does not fall back to articles?' do
          expect(klass.instance_methods(false)).to include(:extractable?)
        end
      end
    end
  end

  describe '.from(parsed_body, opts)' do
    context 'when suitable scraper is found' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><article><a href="/article-1">Article 1</a></article></body></html>')
      end

      it 'returns an array of scrapers' do
        expect(described_class.from(parsed_body)).to be_an(Array)
      end
    end

    context 'when fallback html detection depends on relative links' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <body>
              <section class="cards">
                <div class="card"><h2><a href="/news/launch-update">Launch update</a></h2></div>
                <div class="card"><h2><a href="/news/api-rollout">API rollout</a></h2></div>
              </section>
            </body>
          </html>
        HTML
      end

      let(:opts) do
        Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].transform_values do |config|
          config.merge(enabled: false)
        end.merge(html: { enabled: true })
      end

      it 'still selects the html scraper' do
        expect(described_class.from(parsed_body, opts)).to eq([Html2rss::AutoSource::Scraper::Html])
      end
    end

    context 'when no suitable scraper is found' do
      let(:parsed_body) { Nokogiri::HTML('<html><body></body></html>') }

      it 'raises NoScraperFound error' do
        expect { described_class.from(parsed_body) }
          .to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound, /unsupported extraction surface for auto mode/)
      end
    end

    context 'when the document looks like an anti-bot interstitial' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><title>Just a moment...</title></head>' \
          '<body>Checking your browser before accessing example.com.</body></html>'
        )
      end

      it 'raises a blocked-surface categorized NoScraperFound error', :aggregate_failures do
        expect { described_class.from(parsed_body) }
          .to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound) { |error|
            expect(error.category).to eq(:blocked_surface)
            expect(error.message).to include('blocked surface likely (anti-bot or interstitial)')
          }
      end
    end

    context 'when the document looks like a client-rendered app shell' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><body><div id="root"></div><script src="/assets/app.js"></script></body></html>'
        )
      end

      it 'raises an app-shell categorized NoScraperFound error', :aggregate_failures do
        expect { described_class.from(parsed_body) }
          .to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound) { |error|
            expect(error.category).to eq(:app_shell)
            expect(error.message).to include('app-shell surface detected')
          }
      end
    end

    context 'when the document is a dense high-entropy hub with no extractable articles' do
      let(:parsed_body) do
        links = Array.new(Html2rss::AutoSource::Scraper::HIGH_ENTROPY_MIN_ANCHORS) do |index|
          %(<a href="/dating/pad-#{index}">Pad #{index}</a>)
        end.join
        Nokogiri::HTML("<html><body>#{links}</body></html>")
      end

      it 'classifies the surface as high_entropy_surface', :aggregate_failures do
        category = described_class.classify_no_scraper_surface(parsed_body)

        expect(category).to eq(:high_entropy_surface)
        expect(Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(category))
          .to include('listing/update URL')
      end
    end

    context 'when the app shell has long script/style content' do
      let(:parsed_body) do
        html = '<html><body><div id="root"></div>' \
               "<script>#{'x' * 1_000}</script>" \
               "<style>#{'y' * 1_000}</style></body></html>"
        Nokogiri::HTML(
          html
        )
      end

      it 'still classifies as app_shell by measuring only visible text', :aggregate_failures do
        expect { described_class.from(parsed_body) }
          .to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound) { |error|
            expect(error.category).to eq(:app_shell)
            expect(error.message).to include('app-shell surface detected')
          }
      end
    end
  end

  describe '.build_instance' do
    let(:parsed_body) do
      Nokogiri::HTML('<html><body><article><a href="/article-1">Article 1</a></article></body></html>')
    end
    let(:url) { Html2rss::Url.from_absolute('https://example.com') }
    let(:opts) do
      Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].transform_values do |config|
        config.merge(enabled: false)
      end.merge(
        semantic_html: { enabled: true },
        html: { enabled: true }
      )
    end
    let(:document) { Html2rss::SST::Normalizer.call(parsed_body) }
    let(:link_resolver) { Html2rss::Scoring::LinkResolver.new(url) }

    it 'reuses the provided SST::Document without re-normalizing' do # rubocop:disable RSpec/ExampleLength
      shared_document = document
      allow(Html2rss::SST::Normalizer).to receive(:call)

      described_class::HEURISTIC_SCRAPERS.each do |klass|
        instance = described_class.build_instance(klass, parsed_body, opts:, url:, document: shared_document)
        instance.extractable?
      end

      expect(Html2rss::SST::Normalizer).not_to have_received(:call)
    end

    it 'reuses the provided LinkResolver without constructing another' do # rubocop:disable RSpec/ExampleLength
      shared_resolver = link_resolver
      allow(Html2rss::Scoring::LinkResolver).to receive(:new)

      described_class::HEURISTIC_SCRAPERS.each do |klass|
        instance = described_class.build_instance(
          klass, parsed_body, opts:, url:, document:, link_resolver: shared_resolver
        )
        instance.extractable?
      end

      expect(Html2rss::Scoring::LinkResolver).not_to have_received(:new)
    end
  end

  describe '.heuristic_tier?' do
    it 'is true for tiers that contain a heuristic scraper', :aggregate_failures do
      expect(described_class.heuristic_tier?([described_class::SemanticHtml])).to be(true)
      expect(described_class.heuristic_tier?([described_class::Schema, described_class::Html])).to be(true)
    end

    it 'is false for tiers without heuristic scrapers', :aggregate_failures do
      expect(described_class.heuristic_tier?([described_class::Schema, described_class::Microdata])).to be(false)
      expect(described_class.heuristic_tier?([])).to be(false)
    end
  end

  describe '.from(parsed_body, opts) enablement' do
    let(:parsed_body) do
      Nokogiri::HTML(<<~HTML)
        <html><body><section class="cards">
          <div class="card"><h2><a href="/news/launch-update">Launch update</a></h2></div>
          <div class="card"><h2><a href="/news/api-rollout">API rollout</a></h2></div>
        </section></body></html>
      HTML
    end

    it 'raises when every scraper is disabled in opts' do
      opts = Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].transform_values { |config| config.merge(enabled: false) }

      expect { described_class.from(parsed_body, opts) }
        .to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound, /unsupported extraction surface/)
    end

    it 'ignores scrapers whose options are absent from opts' do
      expect(described_class.from(parsed_body, { html: { enabled: true } }))
        .to eq([Html2rss::AutoSource::Scraper::Html])
    end
  end

  describe '.build_instance enablement and construction' do
    let(:parsed_body) do
      Nokogiri::HTML('<html><body><article><a href="/article-1">Article 1</a></article></body></html>')
    end
    let(:url) { Html2rss::Url.from_absolute('https://example.com') }
    let(:document) { Html2rss::SST::Normalizer.call(parsed_body) }
    let(:resolver) { Html2rss::Scoring::LinkResolver.new(url) }

    it 'returns nil when the scraper is disabled or missing from opts', :aggregate_failures do
      expect(described_class.build_instance(described_class::Schema, parsed_body, opts: {}, url:)).to be_nil
      expect(
        described_class.build_instance(described_class::Schema, parsed_body, opts: { schema: { enabled: false } }, url:)
      ).to be_nil
    end

    it 'returns nil for heuristic scrapers when no shared document is given' do
      opts = { semantic_html: { enabled: true } }

      expect(described_class.build_instance(described_class::SemanticHtml, parsed_body, opts:, url:)).to be_nil
    end

    it 'passes the document, link resolver and scraper options to heuristic scrapers', :aggregate_failures do
      allow(described_class::SemanticHtml).to receive(:new).and_return(:semantic)
      opts = { semantic_html: { enabled: true, max: 3 } }

      result = described_class.build_instance(
        described_class::SemanticHtml, parsed_body, opts:, url:, document:, link_resolver: resolver
      )

      expect(result).to eq(:semantic)
      expect(described_class::SemanticHtml).to have_received(:new)
        .with(parsed_body, url:, document:, link_resolver: resolver, max: 3)
    end

    it 'omits link_resolver for heuristic scrapers when none is given' do
      allow(described_class::Html).to receive(:new).and_return(:html)
      opts = { html: { enabled: true } }

      described_class.build_instance(described_class::Html, parsed_body, opts:, url:, document:)

      expect(described_class::Html).to have_received(:new).with(parsed_body, url:, document:)
    end

    it 'passes request_session only to request-session scrapers', :aggregate_failures do
      allow(described_class::NativeFeed).to receive(:new).and_return(:feed)
      allow(described_class::Schema).to receive(:new).and_return(:schema)
      opts = { native_feed: { enabled: true }, schema: { enabled: true } }

      described_class.build_instance(described_class::NativeFeed, parsed_body, opts:, url:, request_session: :session)
      described_class.build_instance(described_class::Schema, parsed_body, opts:, url:, request_session: :session)

      expect(described_class::NativeFeed).to have_received(:new).with(parsed_body, url:, request_session: :session)
      expect(described_class::Schema).to have_received(:new).with(parsed_body, url:)
    end

    it 'passes the raw body only to Sitemap', :aggregate_failures do
      allow(described_class::Sitemap).to receive(:new).and_return(:sitemap)
      opts = { sitemap: { enabled: true } }

      described_class.build_instance(
        described_class::Sitemap, parsed_body, opts:, url:, body: '<urlset/>', request_session: :session
      )

      expect(described_class::Sitemap).to have_received(:new)
        .with(parsed_body, url:, request_session: :session, body: '<urlset/>')
    end

    it 'defaults captured_responses to an empty array for XhrArticles' do
      allow(described_class::XhrArticles).to receive(:new).and_return(:xhr)

      opts = { xhr_articles: { enabled: true } }

      described_class.build_instance(described_class::XhrArticles, parsed_body, opts:, url:)

      expect(described_class::XhrArticles).to have_received(:new).with(parsed_body, url:, captured_responses: [])
    end

    it 'passes captured responses only to XhrArticles' do
      allow(described_class::XhrArticles).to receive(:new).and_return(:xhr)
      captured = [{ 'items' => [] }]
      opts = { xhr_articles: { enabled: true } }

      described_class.build_instance(described_class::XhrArticles, parsed_body, opts:, url:,
                                                                                captured_responses: captured)

      expect(described_class::XhrArticles).to have_received(:new).with(parsed_body, url:, captured_responses: captured)
    end
  end

  describe '.classify_no_scraper_surface' do
    let(:classify) { ->(html) { described_class.classify_no_scraper_surface(Nokogiri::HTML(html)) } }
    let(:interstitial_html) do
      '<html><head><title>Just a moment...</title></head>' \
        '<body>Checking your browser before accessing example.com.</body></html>'
    end
    let(:benign_html) { '<html><body><p>Plain page</p></body></html>' }

    it 'prefers the raw body over the parsed document for blocked detection', :aggregate_failures do
      expect(described_class.classify_no_scraper_surface(Nokogiri::HTML(benign_html), body: interstitial_html))
        .to eq(:blocked_surface)
      expect(described_class.classify_no_scraper_surface(Nokogiri::HTML(interstitial_html), body: benign_html))
        .to eq(:unsupported_surface)
    end

    it 'falls back to the parsed document when no body is given' do
      expect(classify.call(interstitial_html)).to eq(:blocked_surface)
    end

    it 'classifies blocked surfaces before high-entropy surfaces' do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS) { |index| %(<a href="/x/#{index}">X #{index}</a>) }
      html = interstitial_html.sub('<body>', "<body>#{links.join}")

      expect(classify.call(html)).to eq(:blocked_surface)
    end

    it 'classifies app shells, and high-entropy hubs ahead of app shells', :aggregate_failures do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS) { |index| %(<a href="/x/#{index}">X #{index}</a>) }

      expect(classify.call('<html><body><div id="root"></div></body></html>')).to eq(:app_shell)
      expect(classify.call("<html><body>#{links.join}</body></html>")).to eq(:high_entropy_surface)
      expect(classify.call(%(<html><body><div id="root"></div>#{links.join}</body></html>)))
        .to eq(:high_entropy_surface)
    end

    it 'classifies an empty page as unsupported' do
      expect(classify.call('<html><body></body></html>')).to eq(:unsupported_surface)
    end
  end

  describe '.app_shell_surface?' do
    let(:classify) { ->(html) { described_class.classify_no_scraper_surface(Nokogiri::HTML(html)) } }

    it 'detects app shells for every root marker', :aggregate_failures do
      markers = [
        '<div id="app"></div>', '<div id="root"></div>', '<div id="__next"></div>',
        '<div data-reactroot></div>', '<div ng-app></div>', '<div id="site-app-shell"></div>'
      ]

      expect(markers.map { |marker| classify.call("<html><body>#{marker}</body></html>") })
        .to all(eq(:app_shell))
    end

    it 'does not treat a page without a root marker as an app shell' do
      expect(classify.call('<html><body><div id="main"></div></body></html>')).to eq(:unsupported_surface)
    end

    it 'tolerates up to APP_SHELL_MAX_ANCHORS anchors but not one more', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_ANCHORS
      within = Array.new(limit) { |index| %(<a href="/n/#{index}">N #{index}</a>) }.join
      over = Array.new(limit + 1) { |index| %(<a href="/n/#{index}">N #{index}</a>) }.join

      expect(classify.call(%(<html><body><div id="root"></div>#{within}</body></html>))).to eq(:app_shell)
      expect(classify.call(%(<html><body><div id="root"></div>#{over}</body></html>))).to eq(:unsupported_surface)
    end

    it 'rejects pages that carry article markers', :aggregate_failures do
      markers = [
        '<article>Story</article>',
        '<div itemtype="https://schema.org/NewsArticle">Story</div>',
        '<div itemprop="articleBody">Story</div>'
      ]

      expect(markers.map { |marker| classify.call(%(<html><body><div id="root"></div>#{marker}</body></html>)) })
        .to all(eq(:unsupported_surface))
    end

    it 'accepts visible text up to APP_SHELL_MAX_VISIBLE_TEXT_LENGTH but not one more', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH

      expect(classify.call(%(<html><body><div id="root"><p>#{'a' * limit}</p></div></body></html>)))
        .to eq(:app_shell)
      expect(classify.call(%(<html><body><div id="root"><p>#{'a' * (limit + 1)}</p></div></body></html>)))
        .to eq(:unsupported_surface)
    end
  end

  describe '.visible_text_length' do
    let(:classify) { ->(html) { described_class.classify_no_scraper_surface(Nokogiri::HTML(html)) } }

    it 'ignores script, style and noscript content', :aggregate_failures do
      html = '<html><body><div id="root"></div>' \
             "<noscript>#{'n' * 1_000}</noscript><style>#{'s' * 1_000}</style></body></html>"

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'collapses whitespace-only text to zero length' do
      html = %(<html><body><div id="root"></div><p>#{' ' * 1_000}</p></body></html>)

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'trims and collapses whitespace before measuring', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH
      padded = %(<html><body><div id="root"><p>   #{'a' * limit}   </p></div></body></html>)
      spaced = %(<html><body><div id="root"><p>a#{' ' * 1_000}b</p></div></body></html>)
      word_run = %(<html><body><div id="root"><p>#{'a ' * limit.div(2)}a</p></div></body></html>)

      expect(classify.call(padded)).to eq(:app_shell)
      expect(classify.call(spaced)).to eq(:app_shell)
      expect(classify.call(word_run)).to eq(:unsupported_surface)
    end

    it 'joins separate text nodes with a single space' do
      half = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH / 2
      html = %(<html><body><div id="root"><p>#{'a' * half}</p><p>#{'b' * half}</p></div></body></html>)

      expect(classify.call(html)).to eq(:unsupported_surface)
    end

    it 'ignores text outside the body element' do
      html = %(<html><head><title>#{'t' * 300}</title></head><body><div id="root"></div></body></html>)

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'returns zero for a document without a body element' do
      document = Nokogiri::HTML::Document.new
      html_node = document.add_child(Nokogiri::XML::Node.new('html', document))
      html_node.add_child(Nokogiri::XML::Node.new('div', document).tap { |node| node['id'] = 'root' })

      expect(described_class.classify_no_scraper_surface(document)).to eq(:app_shell)
    end
  end

  describe '.high_entropy_surface?' do
    let(:classify) { ->(html) { described_class.classify_no_scraper_surface(Nokogiri::HTML(html)) } }

    it 'holds for hubs well beyond HIGH_ENTROPY_MIN_ANCHORS' do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS + 5) do |index|
        %(<a href="/q/#{index}">Q #{index}</a>)
      end

      expect(classify.call("<html><body>#{links.join}</body></html>")).to eq(:high_entropy_surface)
    end

    it 'requires HIGH_ENTROPY_MIN_ANCHORS anchors', :aggregate_failures do
      limit = described_class::HIGH_ENTROPY_MIN_ANCHORS
      at_limit = Array.new(limit) { |index| %(<a href="/p/#{index}">P #{index}</a>) }.join
      below = Array.new(limit - 1) { |index| %(<a href="/p/#{index}">P #{index}</a>) }.join

      expect(classify.call("<html><body>#{at_limit}</body></html>")).to eq(:high_entropy_surface)
      expect(classify.call("<html><body>#{below}</body></html>")).to eq(:unsupported_surface)
    end
  end

  describe '.no_scraper_found_for' do
    it 'builds a NoScraperFound carrying the classified category', :aggregate_failures do
      error = described_class.no_scraper_found_for(Nokogiri::HTML('<html><body></body></html>'))

      expect(error).to be_a(Html2rss::AutoSource::Scraper::NoScraperFound)
      expect(error.category).to eq(:unsupported_surface)
    end

    it 'uses the raw body for blocked-surface classification' do
      interstitial = '<html><head><title>Just a moment...</title></head>' \
                     '<body>Checking your browser before accessing example.com.</body></html>'
      error = described_class.no_scraper_found_for(Nokogiri::HTML('<html><body></body></html>'), body: interstitial)

      expect(error.category).to eq(:blocked_surface)
    end
  end

  describe Html2rss::AutoSource::Scraper::NoScraperFound do
    it 'raises a clear error for unknown categories' do
      expect { described_class.new(category: :bogus) }
        .to raise_error(ArgumentError, /Unknown category: :bogus/)
    end
  end
end

# rubocop:enable RSpec/ExampleLength
