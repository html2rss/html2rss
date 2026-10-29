# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BlockedSurface do
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

    it 'returns false for nil' do
      expect(described_class.interstitial?(nil)).to be(false)
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b.force_encoding(Encoding::UTF_8)
      expect { described_class.interstitial?(body) }.not_to raise_error
      expect(described_class.interstitial?(body)).to be(false)
    end

    it 'requires min_matches to be satisfied before detecting an interstitial', :aggregate_failures do
      expect(described_class.interstitial?('<title>Just a moment...</title>')).to be(false)
      expect(described_class.interstitial?('<title>Just a moment...</title> cloudflare ray id')).to be(true)
    end
  end

  describe '.interstitial_signature_for' do
    it 'returns nil for nil body' do
      expect(described_class.interstitial_signature_for(nil)).to be_nil
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b.force_encoding(Encoding::UTF_8)
      expect { described_class.interstitial_signature_for(body) }.not_to raise_error
      expect(described_class.interstitial_signature_for(body)).to be_nil
    end

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

    it 'returns the 403 Forbidden signature key' do
      expect(described_class.interstitial_signature_for('<title>403 Forbidden</title><h1>403 Forbidden</h1>')[:key])
        .to eq(:http_403_forbidden)
    end
  end
end
