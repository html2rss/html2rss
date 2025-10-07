# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::RequestHeaders do
  subject(:normalized) do
    described_class.normalize(headers, channel_language:, url:)
  end

  let(:headers) { {} }
  let(:channel_language) { 'de-DE' }
  let(:url) { 'https://example.com/feed' }

  describe '.browser_defaults' do
    it 'returns a mutable copy of the default headers' do
      expect { described_class.browser_defaults['User-Agent'] = 'Custom' }
        .not_to(change { described_class.browser_defaults['User-Agent'] })
    end
  end

  describe '#to_h' do
    context 'when no overrides are provided' do
      it 'adds Accept-Language from the channel language' do
        expect(normalized).to include('Accept-Language' => 'de-DE,de;q=0.9')
      end

      it 'infers the Host header from the URL' do
        expect(normalized).to include('Host' => 'example.com')
      end
    end

    context 'when overrides are provided' do
      let(:headers) do
        { 'accept' => 'application/json', 'x-test-header' => 'abc' }
      end

      it 'capitalizes custom header keys' do
        expect(normalized).to include('X-Test-Header' => 'abc')
      end

      it 'prepends custom Accept values while keeping defaults' do
        expected = "application/json,#{described_class::DEFAULT_ACCEPT}"

        expect(normalized).to include('Accept' => expected)
      end
    end

    context 'when the channel language is blank' do
      let(:channel_language) { '  ' }

      it 'falls back to en-US' do
        expect(normalized).to include('Accept-Language' => 'en-US,en;q=0.9')
      end
    end

    context 'when the URL is blank' do
      let(:url) { nil }

      it 'does not add a Host header' do
        expect(normalized).not_to include('Host')
      end
    end
  end
end
