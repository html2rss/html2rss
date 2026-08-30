# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BlockedSurface do
  # Shared corpus owned by botasaurus-scrape-api (sibling under the org workspace).
  challenge_fixture_root = Pathname(__dir__)
                              .join('../../../../../botasaurus-scrape-api/tests/fixtures/challenge')
                              .expand_path

  def self.load_challenge_fixture(name, root:)
    path = root.join(name)
    skip "challenge corpus missing at #{path} (clone botasaurus-scrape-api sibling)" unless path.file?

    path.read
  end

  describe '.interstitial? against shared challenge corpus' do
    it 'returns true for cloudflare_interstitial.html' do
      body = self.class.load_challenge_fixture('cloudflare_interstitial.html', root: challenge_fixture_root)
      expect(described_class.interstitial?(body)).to be(true)
    end

    it 'returns true for datadome_interstitial.html' do
      body = self.class.load_challenge_fixture('datadome_interstitial.html', root: challenge_fixture_root)
      expect(described_class.interstitial?(body)).to be(true)
    end

    it 'returns true for vercel_checkpoint.html' do
      body = self.class.load_challenge_fixture('vercel_checkpoint.html', root: challenge_fixture_root)
      expect(described_class.interstitial?(body)).to be(true)
    end

    it 'returns false for clean.html' do
      body = self.class.load_challenge_fixture('clean.html', root: challenge_fixture_root)
      expect(described_class.interstitial?(body)).to be(false)
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b
      expect { described_class.interstitial?(body) }.not_to raise_error
      expect(described_class.interstitial?(body)).to be(false)
    end
  end

  describe '.interstitial_signature_for' do
    it 'returns the DataDome signature key for datadome_interstitial.html' do
      body = self.class.load_challenge_fixture('datadome_interstitial.html', root: challenge_fixture_root)
      expect(described_class.interstitial_signature_for(body)[:key]).to eq(:datadome_interstitial)
    end

    it 'returns the Vercel signature key for vercel_checkpoint.html' do
      body = self.class.load_challenge_fixture('vercel_checkpoint.html', root: challenge_fixture_root)
      expect(described_class.interstitial_signature_for(body)[:key]).to eq(:vercel_security_checkpoint)
    end

    it 'returns the Cloudflare signature key for cloudflare_interstitial.html' do
      body = self.class.load_challenge_fixture('cloudflare_interstitial.html', root: challenge_fixture_root)
      expect(described_class.interstitial_signature_for(body)[:key]).to eq(:cloudflare_interstitial)
    end
  end
end
