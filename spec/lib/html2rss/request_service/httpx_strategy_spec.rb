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
      relation: :initial,
      advertisement: nil
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
           '<body>Checking your browser before accessing example.com.</body></html>'
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
        relation: :initial,
        advertisement: nil
      )
      expect(result.status).to eq(200)
      expect(result.body).to eq('<html>final</html>')
      expect(result.url.to_s).to eq('https://example.com/final')
    end

    it 'validates hops of an advertised feed with the page advertisement' do # rubocop:disable RSpec/ExampleLength -- redirect verification
      advertisement = Html2rss::RequestService::FeedAdvertisement.from_document(
        Nokogiri::HTML('<head></head>'), page_url: 'https://example.com/'
      )
      ctx = Html2rss::RequestService::Context.new(url: 'https://example.com', policy:, budget:,
                                                  relation: :advertised_feed, advertisement:)
      stub_request(:get, 'https://example.com').to_return(status: 301,
                                                          headers: { 'Location' => 'https://example.net/f' })
      stub_request(:get, 'https://example.net/f').to_return(status: 200, body: '<rss></rss>')

      described_class.new(ctx).execute

      expect(policy).to have_received(:validate_redirect!).with(hash_including(advertisement:))
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

    it 'maps HTTPX::ConnectionError to ConnectionFailed' do
      stub_request(:get, 'https://example.com')
        .to_raise(HTTPX::ConnectionError.new('connection refused'))

      expect { execute }.to raise_error(Html2rss::RequestService::ConnectionFailed, /connection refused/)
    end

    it 'maps HTTPX::ServerSideRequestForgeryError to PrivateNetworkDenied' do
      stub_request(:get, 'https://example.com')
        .to_raise(HTTPX::ServerSideRequestForgeryError.new('127.0.0.1 not allowed'))

      expect { execute }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /127.0.0.1/)
    end

    # rubocop:disable-next RSpec/ExampleLength -- slot spend plus per-request retry override
    it 'maps HTTPX retry recursion SystemStackError to ConnectionFailed after one budget slot',
       :aggregate_failures do
      session = instance_double(HTTPX::Session)
      allow(described_class).to receive_messages(base_session: session, base_ssrf_session: session)
      allow(session).to receive(:with).and_return(session)
      allow(session).to receive(:get).and_raise(SystemStackError, 'stack level too deep')

      expect { execute }.to raise_error(Html2rss::RequestService::ConnectionFailed, /retry recursion/)
      expect(budget).to have_received(:consume!)
      expect(session).to have_received(:with).with(
        hash_including(
          max_retries: 0,
          retry_after: described_class::RETRY_AFTER_SECONDS
        )
      )
    end
  end

  describe 'HTTPX retry configuration' do
    subject(:options) { described_class.base_session.class.default_options }

    it 'bounds retries on the selector timer path so ping reconnects cannot recurse', :aggregate_failures do
      expect(options.max_retries).to eq(described_class::MAX_RETRIES)
      expect(options.retry_after).to eq(described_class::RETRY_AFTER_SECONDS)
    end

    # rubocop:disable-next RSpec/ExampleLength -- deadline-bounded Ruby retries vs plugin
    it 'retries TimeoutError in Ruby without consuming extra budget slots', :aggregate_failures do
      session = instance_double(HTTPX::Session)
      timeout = HTTPX::TimeoutError.new({ request_timeout: 5 }, 'timed out')
      raw_response = instance_double(
        HTTPX::Response,
        status: 200,
        body: StringIO.new('<html>ok</html>'),
        headers: instance_double(HTTPX::Headers, to_h: { 'content-type' => 'text/html' }),
        uri: URI('https://example.com')
      )
      outcomes = [timeout, timeout, raw_response]
      allow(described_class).to receive_messages(base_session: session, base_ssrf_session: session)
      allow(session).to receive(:with).and_return(session)
      allow(session).to receive(:get) do
        outcome = outcomes.shift
        raise outcome if outcome.is_a?(Exception)

        outcome
      end

      expect(execute.status).to eq(200)
      expect(budget).to have_received(:consume!).once
      expect(session).to have_received(:get).exactly(3).times
      expect(session).to have_received(:with).with(hash_including(max_retries: 0)).at_least(:once)
    end
  end

  describe 'per-request deadline ceiling' do
    # Single probe bag keeps this group at the MultipleMemoizedHelpers ceiling.
    let(:deadline_probe) do
      timeouts = {}
      session = instance_double(HTTPX::Session)
      raw_response = instance_double(
        HTTPX::Response,
        status: 200,
        body: StringIO.new('<html>ok</html>'),
        headers: instance_double(HTTPX::Headers, to_h: { 'content-type' => 'text/html' }),
        uri: URI('https://example.com')
      )
      allow(described_class).to receive_messages(base_session: session, base_ssrf_session: session)
      allow(session).to receive(:with) do |options|
        timeouts.replace(options.fetch(:timeout))
        session
      end
      allow(session).to receive(:get).and_return(raw_response)
      { timeouts: }
    end

    # rubocop:disable-next RSpec/ExampleLength -- budget vs ceiling timeout wiring
    it 'caps operation_timeout and total_request_timeout at connect + read when budget is larger',
       :aggregate_failures do
      allow(policy).to receive_messages(total_timeout_seconds: 50, connect_timeout_seconds: 5,
                                        read_timeout_seconds: 10)
      allow(budget).to receive(:effective_timeout_seconds).with(fallback: 50).and_return(50.0)
      timeouts = deadline_probe.fetch(:timeouts)

      execute

      expect(timeouts[:operation_timeout]).to be_within(0.05).of(15.0)
      expect(timeouts[:request_timeout]).to be_within(0.05).of(15.0)
      expect(timeouts[:total_request_timeout]).to be_within(0.05).of(15.0)
    end

    # rubocop:disable-next RSpec/ExampleLength -- remaining budget still wins when smaller
    it 'respects a smaller remaining budget deadline below the connect + read ceiling',
       :aggregate_failures do
      allow(policy).to receive_messages(total_timeout_seconds: 50, connect_timeout_seconds: 5,
                                        read_timeout_seconds: 10)
      allow(budget).to receive(:effective_timeout_seconds).with(fallback: 50).and_return(4.0)
      timeouts = deadline_probe.fetch(:timeouts)

      execute

      expect(timeouts[:operation_timeout]).to be_within(0.05).of(4.0)
      expect(timeouts[:request_timeout]).to be_within(0.05).of(4.0)
      expect(timeouts[:total_request_timeout]).to be_within(0.05).of(4.0)
    end
  end
end

RSpec.describe Html2rss::RequestService::HttpxStrategy, 'NAT64 SSRF filtering' do
  let(:guard) { Html2rss::RequestService::NetworkGuard.new(allow_private_networks: false) }
  let(:url) { Html2rss::Url.from_absolute('https://nat64.test/feed') }
  let(:denied) { Html2rss::RequestService::PrivateNetworkDenied }

  before { allow(HTTPX::TCP).to receive(:new).and_call_original }

  # Runs the real HTTPX stack (filter, connection, socket layer) with the HTTP mocks stepped aside.
  # Resolution is stubbed through HTTPX's +addresses+ option: no DNS, no network. The session is
  # built here, not memoized, so the mock-free session never leaks into other examples.
  def fetch(ip)
    WebMock.disable!
    VCR.turned_off do
      HTTPX.plugin(:html2rss_network_guard)
           .with(addresses: { 'nat64.test' => [ip] }, timeout: { connect_timeout: 0.2 })
           .get('https://nat64.test/feed')
    end
  ensure
    WebMock.enable!
  end

  it 'loads the guard filter ahead of ssrf_filter in connection method resolution' do
    ancestors = described_class.base_ssrf_session.class.default_options.connection_class.ancestors

    expect(ancestors.index(Html2rss::RequestService::NetworkGuardFilter::ConnectionMethods))
      .to be < ancestors.index(HTTPX::Plugins::SsrfFilter::ConnectionMethods)
  end

  describe Html2rss::RequestService::NetworkGuardFilter do
    it 'releases only the NAT64 prefix from the ssrf filter' do
      expect(described_class.extra_options({})).to eq(safe_private_ranges: [Html2rss::RequestService::NetworkGuard::NAT64_PREFIX])
    end

    it 'does not deny public addresses without an embedded IPv4', :aggregate_failures do
      expect(described_class.denied?(IPAddr.new('2001:4860:4860::8888'))).to be(false)
      expect(described_class.denied?(IPAddr.new('8.8.8.8'))).to be(false)
    end

    it 'denies private and mapped-private addresses', :aggregate_failures do
      expect(described_class.denied?(IPAddr.new('10.0.0.1'))).to be(true)
      expect(described_class.denied?(IPAddr.new('::ffff:10.0.0.1'))).to be(true)
    end

    it 'denies per address entry through the guard', :aggregate_failures do
      base = Class.new do
        attr_reader :got

        def addresses=(addrs)
          @got = addrs
        end
      end
      conn = base.tap { |k| k.prepend(described_class::ConnectionMethods) }.new
      entry = Struct.new(:address)
      conn.addresses = [entry.new(IPAddr.new('64:ff9b::10.0.0.1')), entry.new(IPAddr.new('64:ff9b::8.8.8.8'))]

      expect(conn.got.map { |e| e.address.to_s }).to eq(['64:ff9b::808:808'])
    end
  end

  %w[64:ff9b::10.0.0.1 64:ff9b::169.254.169.254 64:ff9b:1::808:808
     2002:0a00:0001:: 2001::1].each do |ip|
    it "refuses #{ip} before any socket is opened and the guard agrees", :aggregate_failures do
      response = fetch(ip)

      expect(response.error).to be_a(HTTPX::ServerSideRequestForgeryError)
      expect(HTTPX::TCP).not_to have_received(:new)
      expect { guard.validate_remote_ip!(ip:, url:) }.to raise_error(denied)
    end
  end

  it 'fails closed on a NAT64 address whose IPv4 only the HTTPX list denies', :aggregate_failures do
    response = fetch('64:ff9b::100.64.0.1')

    expect(response.error).to be_a(HTTPX::ServerSideRequestForgeryError)
    expect(HTTPX::TCP).not_to have_received(:new)
  end

  it 'lets a public NAT64 address reach the socket layer and the guard accepts the peer', :aggregate_failures do
    response = fetch('64:ff9b::8.8.8.8')

    expect(response.error).not_to be_a(HTTPX::ServerSideRequestForgeryError)
    expect(HTTPX::TCP).to have_received(:new)
    expect { guard.validate_remote_ip!(ip: '64:ff9b::8.8.8.8', url:) }.not_to raise_error
  end
end
