# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Error do
  it { expect(described_class).to be < StandardError }

  describe Html2rss::NoFeedItemsExtracted do
    let(:attempts) { [{ strategy: :faraday, items_count: 0, error_class: nil }] }

    it 'keeps the base empty-feed message without a surface hint', :aggregate_failures do
      error = described_class.new(attempts:)

      expect(error.message).to include('No feed items extracted after auto fallback')
      expect(error.message).not_to include('app-shell surface detected')
    end

    it 'appends shared Scraper guidance for app_shell', :aggregate_failures do
      error = described_class.new(attempts:, surface_category: :app_shell)
      guidance = Html2rss::AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(:app_shell)

      expect(error.surface_category).to eq(:app_shell)
      expect(error.message).to include(guidance)
      expect(error.message).not_to include('No scrapers found:')
    end
  end
end
