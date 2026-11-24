# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

# rubocop:disable-next RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
RSpec.describe Html2rss::RequestService::BotasaurusStrategy, '#execute' do
  subject(:captured) { described_class.new(ctx).execute.captured_responses.map { _1.fetch('url') } }

  let(:resolver) do
    table = { 'example.com' => '93.184.216.34', 'api.example.net' => '8.8.8.8', 'internal.example' => '10.0.0.7' }
    lookups = self.lookups
    Class.new do
      define_method(:each_address) do |host, &block|
        lookups << host
        raise Resolv::ResolvTimeout if host == 'slow.example'

        block.call(table.fetch(host)) if table.key?(host)
      end
    end.new
  end
  let(:lookups) { [] }
  let(:policy) { Html2rss::RequestService::Policy.new(resolver:) }
  let(:denied) { Html2rss::RequestService::PrivateNetworkDenied }
  let(:budget) { Html2rss::RequestService::Budget.new(max_requests: 5, total_timeout_seconds: 30) }
  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com', policy:, budget:) }
  let(:entries) do
    [
      'https://api.example.net/articles', 'http://10.0.0.7/admin', 'http://localhost:8080/x',
      'https://app.localhost/x', 'https://internal.example/x', '', 'ftp://example.com/x', 'not a url',
      'https://slow.example/x'
    ].map { |url| { 'url' => url, 'body' => '[{"title":"One"}]' } }
  end
  let(:payload) do
    {
      final_url: 'https://example.com/', status_code: 200, html: '<html></html>', xhr_responses: entries,
      diagnostics: { request_id: 'request-id' }
    }
  end

  before do
    stub_request(:post, 'http://localhost:4010/scrape')
      .to_return(status: 200, body: JSON.generate(payload), headers: { 'Content-Type' => 'application/json' })
    allow(Html2rss::Log).to receive(:event).and_return(true)
  end

  around do |example|
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://localhost:4010') { example.run }
  end

  it 'keeps only captures from public web addresses and still succeeds', :aggregate_failures do
    expect(captured).to eq(['https://api.example.net/articles'])
  end

  it 'logs each drop with its reason and the redacted endpoint only', :aggregate_failures do
    captured

    expect(Html2rss::Log).to have_received(:event).exactly(8).times
    expect(Html2rss::Log).to have_received(:event).with(
      :warn, 'botasaurus.capture_dropped', reason: denied.name, endpoint: 'http://10.0.0.7/admin'
    )
    expect(Html2rss::Log).to have_received(:event).with(
      :warn, 'botasaurus.capture_dropped', reason: Html2rss::Url::InvalidUrlError.name, endpoint: 'ftp://example.comx'
    )
  end

  context 'when many captures share a host' do
    let(:entries) { Array.new(4) { |index| { 'url' => "https://api.example.net/#{index}", 'body' => '[]' } } }

    it 'resolves that host once', :aggregate_failures do
      expect(captured.size).to eq(4)
      expect(lookups.count('api.example.net')).to eq(1)
    end
  end

  context 'when a denied host repeats' do
    let(:entries) { Array.new(2) { |index| { 'url' => "https://slow.example/#{index}", 'body' => '[]' } } }

    it 'drops each capture, logs each, and resolves once', :aggregate_failures do
      expect(captured).to eq([])
      expect(lookups.count('slow.example')).to eq(1)
      expect(Html2rss::Log).to have_received(:event).twice
    end
  end
end
