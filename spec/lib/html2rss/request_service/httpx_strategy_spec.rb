# frozen_string_literal: true

require 'spec_helper'
require 'brotli'
require 'stringio'
require 'zlib'

RSpec.describe Html2rss::RequestService::HttpxStrategy do
  subject(:execute) { described_class.new(ctx).execute }

  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      max_redirects: 3,
      total_timeout_seconds: 30,
      connect_timeout_seconds: 5,
      read_timeout_seconds: 10,
      max_response_bytes: 1_048_576,
      max_decompressed_bytes: 5_242_880,
      allow_private_networks?: false,
      validate_request!: nil,
      validate_redirect!: nil,
      validate_remote_ip!: nil
    )
  end
  let(:budget) do
    instance_double(
      Html2rss::RequestService::Budget,
      consume!: nil,
      remaining_timeout_seconds: nil,
      effective_timeout_seconds: 30.0,
      elapsed_seconds: 0.0
    )
  end
  let(:ctx) do
    Html2rss::RequestService::Context.new(
      url: 'https://example.com',
      policy:,
      budget:
    )
  end

  before do
    WebMock.enable!
    stub_request(:get, 'https://example.com')
      .to_return(status: 200, body: '<html>hello</html>', headers: { 'Content-Type' => 'text/html' })
  end

  it 'consumes budget, validates the request, and returns a response', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- core request flow
    result = execute

    expect(budget).to have_received(:consume!)
    expect(policy).to have_received(:validate_request!).with(
      url: ctx.url,
      origin_url: ctx.origin_url,
      relation: :initial
    )
    expect(result).to be_a(Html2rss::RequestService::Response)
    expect(result.body).to eq('<html>hello</html>')
    expect(result.status).to eq(200)
  end

  it 'raises when streamed bytes exceed the configured limit' do # rubocop:disable RSpec/ExampleLength -- byte streaming check
    allow(policy).to receive(:max_response_bytes).and_return(5)
    stub_request(:get, 'https://example.com')
      .to_return(status: 200, body: '1234567890', headers: { 'Content-Type' => 'text/html' })

    expect { execute }.to raise_error(
      Html2rss::RequestService::ResponseTooLarge,
      'Response exceeded 5 bytes'
    )
  end

  it 'raises blocked-surface classification when response body is an anti-bot interstitial' do # rubocop:disable RSpec/ExampleLength -- challenge detection check
    body = '<html><head><title>Just a moment...</title></head>' \
           '<body>Checking your browser before accessing canva.com.</body></html>'
    stub_request(:get, 'https://example.com')
      .to_return(status: 200, body:, headers: { 'Content-Type' => 'text/html' })

    expect { execute }
      .to raise_error(Html2rss::RequestService::BlockedSurfaceDetected, /Blocked surface detected/)
  end

  [
    {
      label: 'gzip',
      encode: lambda { |html|
        StringIO.new.tap { |io| Zlib::GzipWriter.wrap(io) { |gzip| gzip.write(html) } }.string
      }
    },
    {
      label: 'brotli',
      encode: ->(html) { Brotli.deflate(html) }
    }
  ].each do |codec|
    context "when #{codec[:label]} HTML is labeled application/octet-stream" do
      let(:html) { '<!DOCTYPE html><html><body><div>decoded stream</div></body></html>' }

      before do
        stub_request(:get, 'https://example.com')
          .to_return(
            status: 200,
            body: codec[:encode].call(html),
            headers: { 'Content-Type' => 'application/octet-stream' }
          )
      end

      it 'decodes the HTML document before parse' do
        expect(execute.parsed_body.at_css('div').text).to eq('decoded stream')
      end
    end
  end

  describe 'redirect handling' do
    it 'follows redirects and validates hops', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- redirect verification
      stub_request(:get, 'https://example.com')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/final' })
      stub_request(:get, 'https://example.com/final')
        .to_return(status: 200, body: '<html>final</html>', headers: { 'Content-Type' => 'text/html' })

      result = execute

      expect(policy).to have_received(:validate_redirect!).with(
        from_url: ctx.url,
        to_url: Html2rss::Url.from_absolute('https://example.com/final'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(result.status).to eq(200)
      expect(result.body).to eq('<html>final</html>')
      expect(result.url.to_s).to eq('https://example.com/final')
    end

    it 'raises when redirect limit is reached and cannot be retried' do # rubocop:disable RSpec/ExampleLength -- multi-hop redirect limit
      stub_request(:get, 'https://example.com')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/1' })
      stub_request(:get, 'https://example.com/1')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/2' })
      stub_request(:get, 'https://example.com/2')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/3' })
      stub_request(:get, 'https://example.com/3')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/4' })
      stub_request(:get, 'https://example.com/4')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/4' })

      expect { execute }.to raise_error(Html2rss::RequestService::RedirectLimitReached)
    end

    it 'retries the terminal redirect location once and succeeds', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- terminal redirect retry
      stub_request(:get, 'https://example.com')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/1' })
      stub_request(:get, 'https://example.com/1')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/2' })
      stub_request(:get, 'https://example.com/2')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/3' })
      stub_request(:get, 'https://example.com/3')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/terminal' })
      stub_request(:get, 'https://example.com/terminal')
        .to_return(status: 200, body: '<html>terminal-success</html>', headers: { 'Content-Type' => 'text/html' })

      result = execute
      expect(result.status).to eq(200)
      expect(result.body).to eq('<html>terminal-success</html>')
      expect(result.url.to_s).to eq('https://example.com/terminal')
    end

    it 'returns the response without raising RedirectLimitReached for 304 Not Modified' do
      stub_request(:get, 'https://example.com')
        .to_return(status: 304, headers: {})

      expect(execute.status).to eq(304)
    end

    it 'returns the response without raising RedirectLimitReached for 3xx responses without Location header' do
      stub_request(:get, 'https://example.com')
        .to_return(status: 300, body: '<html>choices</html>', headers: { 'Content-Type' => 'text/html' })

      expect(execute.status).to eq(300)
    end
  end

  context 'when upstream returns Content-Encoding br' do
    let(:html) { '<!DOCTYPE html><html><body><div>brotli decoded</div></body></html>' }

    before do
      stub_request(:get, 'https://example.com')
        .to_return(
          status: 200,
          body: Brotli.deflate(html),
          headers: { 'Content-Type' => 'text/html', 'Content-Encoding' => 'br' }
        )
    end

    it 'natively decompresses the brotli response body' do
      expect(execute.body).to eq(html)
    end
  end

  describe 'error translation' do
    it 'maps HTTPX::TimeoutError to RequestTimedOut' do
      stub_request(:get, 'https://example.com')
        .to_raise(HTTPX::TimeoutError.new({ request_timeout: 5 }, 'timed out'))

      expect { execute }.to raise_error(Html2rss::RequestService::RequestTimedOut, /timed out/)
    end

    it 'maps HTTPX::ServerSideRequestForgeryError to PrivateNetworkDenied' do
      stub_request(:get, 'https://example.com')
        .to_raise(HTTPX::ServerSideRequestForgeryError.new('127.0.0.1 not allowed'))

      expect { execute }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /127.0.0.1/)
    end
  end
end
