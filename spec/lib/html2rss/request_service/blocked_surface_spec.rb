# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BlockedSurface do
  # Vendored copy of botasaurus-scrape-api challenge corpus (see spec/fixtures/challenge/README.md).
  def challenge_fixture(name)
    path = Pathname(__dir__).join('../../../fixtures/challenge', name).expand_path
    raise "challenge fixture missing at #{path}" unless path.file?

    path.read
  end

  describe '.interstitial? against shared challenge corpus' do
    it 'returns true for cloudflare_interstitial.html' do
      expect(described_class.interstitial?(challenge_fixture('cloudflare_interstitial.html'))).to be(true)
    end

    it 'returns true for datadome_interstitial.html' do
      expect(described_class.interstitial?(challenge_fixture('datadome_interstitial.html'))).to be(true)
    end

    it 'returns true for vercel_checkpoint.html' do
      expect(described_class.interstitial?(challenge_fixture('vercel_checkpoint.html'))).to be(true)
    end

    it 'returns false for clean.html' do
      expect(described_class.interstitial?(challenge_fixture('clean.html'))).to be(false)
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b
      expect { described_class.interstitial?(body) }.not_to raise_error
      expect(described_class.interstitial?(body)).to be(false)
    end
  end

  describe '.interstitial_signature_for' do
    it 'returns the DataDome signature key for datadome_interstitial.html' do
      expect(described_class.interstitial_signature_for(challenge_fixture('datadome_interstitial.html'))[:key])
        .to eq(:datadome_interstitial)
    end

    it 'returns the Vercel signature key for vercel_checkpoint.html' do
      expect(described_class.interstitial_signature_for(challenge_fixture('vercel_checkpoint.html'))[:key])
        .to eq(:vercel_security_checkpoint)
    end

    it 'returns the Cloudflare signature key for cloudflare_interstitial.html' do
      expect(described_class.interstitial_signature_for(challenge_fixture('cloudflare_interstitial.html'))[:key])
        .to eq(:cloudflare_interstitial)
    end
  end
end
