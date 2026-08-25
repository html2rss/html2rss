# frozen_string_literal: true

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

    it 'flattens tiers into SCRAPERS' do
      expect(described_class::SCRAPERS).to eq(described_class::SCRAPER_TIERS.flatten)
    end

    it 'registers NativeFeed for request sessions' do
      expect(described_class::REQUEST_SESSION_SCRAPERS).to include(
        Html2rss::AutoSource::Scraper::NativeFeed
      )
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

  describe '.normalize_sst / .build_instance' do
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
    let(:document) { described_class.normalize_sst(parsed_body) }
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

  describe Html2rss::AutoSource::Scraper::NoScraperFound do
    it 'raises a clear error for unknown categories' do
      expect { described_class.new(category: :bogus) }
        .to raise_error(ArgumentError, /Unknown category: :bogus/)
    end
  end
end
