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
            expect(error.message).to match(/blocked surface likely \(anti-bot or interstitial\)/)
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
            expect(error.message).to match(/app-shell surface detected/)
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
  end
end
