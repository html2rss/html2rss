# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BlockedSurface do
  describe '.interstitial?' do
    let(:cloudflare_body) do
      '<html><head><title>Just a moment...</title></head>' \
        '<body>Checking your browser before accessing example.com.</body></html>'
    end

    let(:datadome_body) do
      '<html><body>' \
        '<script src="https://ct.captcha-delivery.com/c.js"></script>' \
        '<div>DataDome interstitial challenge</div>' \
        '</body></html>'
    end

    let(:vercel_body) do
      '<html><head><title>Vercel Security Checkpoint</title></head>' \
        '<body>Checking the security of your connection before accessing example.com.</body></html>'
    end

    it 'returns true when a Cloudflare interstitial signature matches' do
      expect(described_class.interstitial?(cloudflare_body)).to be(true)
    end

    it 'returns true when a DataDome interstitial signature matches' do
      expect(described_class.interstitial?(datadome_body)).to be(true)
    end

    it 'returns true when a Vercel Security Checkpoint signature matches' do
      expect(described_class.interstitial?(vercel_body)).to be(true)
    end

    it 'does not raise when body includes invalid byte sequences', :aggregate_failures do
      body = "\xFF\xFE".b
      expect { described_class.interstitial?(body) }.not_to raise_error
      expect(described_class.interstitial?(body)).to be(false)
    end
  end

  describe '.interstitial_signature_for' do
    it 'returns the DataDome signature key when matched' do
      body = '<html><body>captcha-delivery.com DataDome</body></html>'
      expect(described_class.interstitial_signature_for(body)[:key]).to eq(:datadome_interstitial)
    end

    it 'returns the Vercel signature key when matched' do
      body = '<html><title>Vercel Security Checkpoint</title></html>'
      expect(described_class.interstitial_signature_for(body)[:key]).to eq(:vercel_security_checkpoint)
    end
  end
end
