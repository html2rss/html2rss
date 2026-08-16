# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Capture do
  subject(:capture) { described_class }

  let(:url) { 'https://example.com/blog' }
  let(:response_body) { '<html><body>Hello</body></html>' }

  describe '.build' do
    it 'returns a CaptureResult' do
      allow_any_instance_of(described_class).to receive(:fetch_response).and_return(
        instance_double(Html2rss::RequestService::Response,
                        body: response_body,
                        url: Html2rss::Url.from_absolute(url),
                        headers: { 'content-type' => 'text/html' },
                        html_response?: true,
                        parsed_body: Nokogiri::HTML(response_body))
      )
      allow_any_instance_of(described_class).to receive(:extract_articles).and_return([])
      allow(Html2rss::Channel).to receive(:from_response).and_return(
        Html2rss::Channel.new(
          title: 'Example Blog',
          url: Html2rss::Url.from_absolute(url),
          description: 'Latest items from https://example.com/blog',
          language: nil,
          ttl: 360,
          last_build_date: Time.now,
          image: nil,
          author: nil
        )
      )

      result = described_class.build(url)

      expect(result).to be_a(described_class::CaptureResult)
      expect(result.config).to have_key(:channel)
      expect(result.articles_count).to eq(0)
    end
  end

  describe 'CaptureResult' do
    subject(:result) { described_class::CaptureResult.new(config:, articles_count: 5, channel_title: 'Test') }

    let(:config) { { channel: { url: 'https://example.com' } } }

    it 'has config accessor' do
      expect(result.config).to eq(config)
    end

    it 'has articles_count accessor' do
      expect(result.articles_count).to eq(5)
    end

    it 'has channel_title accessor' do
      expect(result.channel_title).to eq('Test')
    end
  end
end

RSpec.describe Html2rss do
  describe '.capture' do
    it 'delegates to Capture.build' do
      config_hash = { channel: { url: 'https://example.com' } }
      capture_result = instance_double(Html2rss::Capture::CaptureResult, config: config_hash)

      allow(Html2rss::Capture).to receive(:build).and_return(capture_result)

      result = described_class.capture('https://example.com')

      expect(Html2rss::Capture).to have_received(:build).with(
        'https://example.com',
        hash_including(strategy: :auto)
      )
      expect(result).to eq(config_hash)
    end
  end
end