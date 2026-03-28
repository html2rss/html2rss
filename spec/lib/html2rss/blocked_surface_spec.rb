# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::BlockedSurface do
  describe '.interstitial?' do
    let(:blocked_body) do
      '<html><head><title>Just a moment...</title></head>' \
        '<body>Checking your browser before accessing example.com.</body></html>'
    end

    it 'returns true when a known interstitial signature matches' do
      expect(described_class.interstitial?(blocked_body)).to be(true)
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b
      expect { described_class.interstitial?(body) }.not_to raise_error
      expect(described_class.interstitial?(body)).to be(false)
    end
  end
end
