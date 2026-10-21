# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Error do
  it { expect(described_class).to be < StandardError }

  it 'exposes mutable attempts and transport_meta for AutoFallback', :aggregate_failures do
    error = described_class.new('boom')
    error.attempts = [{ strategy: :default, items_count: nil, error_class: 'RuntimeError' }]
    error.transport_meta = { 'request_id' => 'req-1' }

    expect(error.attempts.first[:strategy]).to eq(:default)
    expect(error.transport_meta).to eq('request_id' => 'req-1')
  end

  describe Html2rss::NoFeedItemsExtracted do
    let(:attempts) { [{ strategy: :default, items_count: 0, error_class: nil }] }
    let(:botasaurus_hint) { Html2rss::RequestService::BotasaurusConfigurationError::EMPTY_FEED_HINT }

    it 'keeps the base empty-feed message without a surface hint', :aggregate_failures do
      error = described_class.new(attempts:)

      expect(error.message).to include('No feed items extracted after auto fallback')
      expect(error.message).not_to include('app-shell surface detected')
      expect(error.message).not_to include(botasaurus_hint)
    end

    it 'appends shared Scraper guidance for app_shell', :aggregate_failures do
      error = described_class.new(attempts:, surface_category: :app_shell)
      guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:app_shell)

      expect(error.surface_category).to eq(:app_shell)
      expect(error.message).to include(guidance)
      expect(error.message).not_to include('No scrapers found:')
    end

    it 'appends shared Scraper guidance for high_entropy_surface', :aggregate_failures do
      error = described_class.new(attempts:, surface_category: :high_entropy_surface)
      guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:high_entropy_surface)

      expect(error.surface_category).to eq(:high_entropy_surface)
      expect(error.message).to include(guidance)
      expect(error.message).to include('listing/update URL')
    end

    context 'when a BotasaurusConfigurationError attempt is present' do
      let(:attempts) do
        [
          { strategy: :default, items_count: 0, error_class: nil },
          {
            strategy: :botasaurus,
            items_count: nil,
            error_class: 'Html2rss::RequestService::BotasaurusConfigurationError'
          }
        ]
      end

      it 'appends the owned Botasaurus config hint once', :aggregate_failures do
        error = described_class.new(attempts:)

        expect(error.message).to include(botasaurus_hint)
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end

      # rubocop:disable-next RSpec/ExampleLength -- guidance + hint + no twin BOTASAURUS assert
      it 'appends the Botasaurus config hint beside app_shell guidance', :aggregate_failures do
        error = described_class.new(attempts:, surface_category: :app_shell)
        guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:app_shell)

        expect(error.message).to include(guidance)
        expect(error.message).to include(botasaurus_hint)
        expect(guidance).not_to include('BOTASAURUS_SCRAPER_URL')
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end

      it 'does not twin Botasaurus prose when blocked_surface already covers it', :aggregate_failures do
        error = described_class.new(attempts:, surface_category: :blocked_surface)
        guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:blocked_surface)

        expect(error.message).to include(guidance)
        expect(error.message).not_to include(botasaurus_hint)
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end
    end
  end
end
