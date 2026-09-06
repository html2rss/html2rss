# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Error do
  it { expect(described_class).to be < StandardError }

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

      it 'does not twin Botasaurus prose when app_shell already covers it', :aggregate_failures do
        error = described_class.new(attempts:, surface_category: :app_shell)
        guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:app_shell)

        expect(error.message).to include(guidance)
        expect(error.message).not_to include(botasaurus_hint)
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end
    end
  end
end
