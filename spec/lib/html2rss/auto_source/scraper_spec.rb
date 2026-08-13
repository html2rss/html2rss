# frozen_string_literal: true

require 'rspec'

RSpec.describe Html2rss::AutoSource::Scraper do
  it { is_expected.to be_a(Module) }
  it { expect(described_class::SCRAPERS).to be_an(Array) }

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

  describe '.instances_for(parsed_body, url:, opts:)' do
    let(:parsed_body) do
      Nokogiri::HTML('<html><body><article><a href="/article-1">Article 1</a></article></body></html>')
    end
    let(:url) { Html2rss::Url.from_absolute('https://example.com') }

    it 'returns scraper instances that can extract articles' do
      expect(described_class.instances_for(parsed_body, url:)).to all(respond_to(:each))
    end

    context 'when SemanticHtml and Html are both enabled' do
      let(:opts) do
        Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].transform_values do |config|
          config.merge(enabled: false)
        end.merge(
          semantic_html: { enabled: true },
          html: { enabled: true }
        )
      end
      let(:captured_documents) { [] }

      before do
        allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original

        [Html2rss::AutoSource::Scraper::SemanticHtml, Html2rss::AutoSource::Scraper::Html].each do |klass|
          allow(klass).to receive(:new).and_wrap_original do |original, *args, **kwargs|
            captured_documents << kwargs.fetch(:document)
            original.call(*args, **kwargs)
          end
        end
      end

      it 'normalizes once and shares the same SST::Document', :aggregate_failures do
        described_class.instances_for(parsed_body, url:, opts:)

        expect(Html2rss::SST::Normalizer).to have_received(:call).once
        expect(captured_documents.size).to eq(2)
        expect(captured_documents).to all(be_a(Html2rss::SST::Document))
        expect(captured_documents[0]).to equal(captured_documents[1])
      end
    end
  end

  describe Html2rss::AutoSource::Scraper::NoScraperFound do
    it 'raises a clear error for unknown categories' do
      expect { described_class.new(category: :bogus) }
        .to raise_error(ArgumentError, /Unknown category: :bogus/)
    end
  end
end
