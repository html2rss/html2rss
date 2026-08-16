# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zlib'

RSpec.describe Html2rss::RequestService::FaradayStrategy do # rubocop:disable RSpec/MultipleMemoizedHelpers
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
  let(:builder) { instance_double(Faraday::RackBuilder, use: nil, request: nil, adapter: nil) }
  let(:connection) { instance_double(Faraday::Connection) }
  let(:request_options) { Faraday::RequestOptions.new }
  let(:retry_request_options) { Faraday::RequestOptions.new }
  let(:request) { instance_double(Faraday::Request, options: request_options) }
  let(:retry_request) { instance_double(Faraday::Request, options: retry_request_options) }
  let(:response_env) { instance_double(Faraday::Env, url: Addressable::URI.parse('https://example.com')) }
  let(:redirected_env) { instance_double(Faraday::Env, url: Addressable::URI.parse('https://example.com/final')) }
  let(:response) do
    instance_double(
      Faraday::Response,
      body: '<html></html>',
      headers: { 'content-type' => 'text/html' },
      env: response_env,
      status: 200
    )
  end
  let(:empty_redirected_response) do
    instance_double(
      Faraday::Response,
      body: '',
      headers: { 'content-type' => 'text/html' },
      env: redirected_env,
      status: 200
    )
  end
  let(:recovered_response) do
    instance_double(
      Faraday::Response,
      body: '<html>redirected body</html>',
      headers: { 'content-type' => 'text/html' },
      env: redirected_env,
      status: 200
    )
  end

  before do
    allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)
    allow(connection).to receive(:get).and_yield(request).and_return(response)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0, 100.0)
  end

  it 'consumes budget, validates the request, and returns a response', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    result = execute

    expect(budget).to have_received(:consume!)
    expect(policy).to have_received(:validate_request!).with(
      url: ctx.url,
      origin_url: ctx.origin_url,
      relation: :initial
    )
    expect(builder).to have_received(:use).with(
      Faraday::FollowRedirects::Middleware,
      hash_including(limit: policy.max_redirects, callback: kind_of(Proc))
    )
    expect(builder).to have_received(:request).with(:gzip)
    expect(builder).to have_received(:use).with(described_class::StreamingBodyMiddleware)
    expect(request_options.context).to include(
      described_class::StreamingBodyMiddleware::STREAM_BUFFER_KEY => ''
    )
    expect(request_options.on_data).to be_a(Proc)
    expect(result).to be_a(Html2rss::RequestService::Response)
  end

  it 'raises when streamed bytes exceed the configured limit' do # rubocop:disable RSpec/ExampleLength
    allow(policy).to receive(:max_response_bytes).and_return(5)
    allow(connection).to receive(:get) do |&block|
      block.call(request)
      streamed_env = Faraday::Env.from(
        request: request_options,
        response_headers: { 'content-type' => 'text/html' },
        status: 200
      )
      request_options.on_data.call('123', 3, streamed_env)
      request_options.on_data.call('456', 6, streamed_env)
      response
    end

    expect { execute }.to raise_error(
      Html2rss::RequestService::ResponseTooLarge,
      'Response exceeded 5 bytes'
    )
  end

  it 'retries without streaming when a redirected response returns an empty body', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    call_count = 0
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0, 112.4)
    allow(connection).to receive(:get) do |&block|
      call_count += 1
      block&.call(call_count == 1 ? request : retry_request)
      call_count == 1 ? empty_redirected_response : recovered_response
    end

    result = execute

    expect(budget).to have_received(:consume!).once
    expect(policy).to have_received(:validate_request!).twice
    expect(connection).to have_received(:get).twice
    expect(retry_request_options.timeout).to be_within(0.001).of(17.6)
    expect(retry_request_options.open_timeout).to eq(5)
    expect(retry_request_options.read_timeout).to eq(10)
    expect(retry_request_options.on_data).to be_a(Proc)
    expect(retry_request_options.context).to be_nil
    expect(result.body).to eq('<html>redirected body</html>')
    expect(result.url.to_s).to eq('https://example.com/final')
  end

  it 'enforces streamed byte limits on the redirected fallback path' do # rubocop:disable RSpec/ExampleLength
    allow(policy).to receive(:max_response_bytes).and_return(5)

    call_count = 0
    allow(connection).to receive(:get) do |&block|
      call_count += 1
      current_request = call_count == 1 ? request : retry_request
      block.call(current_request)
      current_options = current_request.options
      streamed_env = Faraday::Env.from(
        request: current_options,
        response_headers: { 'content-type' => 'text/html' },
        status: 200
      )
      current_options.on_data.call('123', 3, streamed_env)
      current_options.on_data.call('456', 6, streamed_env) if call_count == 2

      call_count == 1 ? empty_redirected_response : recovered_response
    end

    expect { execute }.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 5 bytes')
  end

  it 'raises blocked-surface classification when response body is an anti-bot interstitial' do
    body = '<html><head><title>Just a moment...</title></head>' \
           '<body>Checking your browser before accessing canva.com.</body></html>'
    allow(response).to receive(:body).and_return(body)

    expect { execute }
      .to raise_error(Html2rss::RequestService::BlockedSurfaceDetected, /Blocked surface detected/)
  end

  describe 'RedirectLimitReached terminal URL retry' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:redirect_callback) { {} }
    let(:terminal_url) { 'https://cdn.example.com/terminal' }
    let(:terminal_env) { instance_double(Faraday::Env, url: Addressable::URI.parse("#{terminal_url}/final")) }
    let(:terminal_response) do
      instance_double(
        Faraday::Response,
        body: '<html>terminal</html>',
        headers: { 'content-type' => 'text/html' },
        env: terminal_env,
        status: 200
      )
    end
    let(:terminal_request) { instance_double(Faraday::Request, options: Faraday::RequestOptions.new) }
    let(:simulate_redirect_hops) do
      lambda do |*hop_urls|
        ([ctx.url.to_s] + hop_urls).each_cons(2) do |from, to|
          redirect_callback[:proc].call(
            { url: Addressable::URI.parse(from) },
            { url: Addressable::URI.parse(to) }
          )
        end
      end
    end

    before do
      allow(builder).to receive(:use) do |klass, options = nil|
        redirect_callback[:proc] = options[:callback] if klass == Faraday::FollowRedirects::Middleware
      end
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0)
    end

    it 're-fetches the last redirect hop once and succeeds', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      call_count = 0
      allow(connection).to receive(:get) do |&block|
        call_count += 1
        block&.call(call_count == 1 ? request : terminal_request)
        if call_count == 1
          simulate_redirect_hops.call('https://cdn.example.com/hop1', terminal_url)
          raise Faraday::FollowRedirects::RedirectLimitReached, 'too many redirects'
        end

        terminal_response
      end

      result = execute

      expect(connection).to have_received(:get).twice
      expect(budget).to have_received(:consume!).once
      expect(policy).to have_received(:validate_redirect!).with(
        from_url: Html2rss::Url.from_absolute('https://cdn.example.com/hop1'),
        to_url: Html2rss::Url.from_absolute(terminal_url),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(policy).to have_received(:validate_request!).with(
        hash_including(url: Html2rss::Url.from_absolute(terminal_url))
      )
      expect(Faraday).to have_received(:new).with(hash_including(url: terminal_url))
      expect(result.body).to eq('<html>terminal</html>')
      expect(result.url.to_s).to eq("#{terminal_url}/final")
    end

    it 'does not retry RedirectLimitReached more than once', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      call_count = 0
      allow(connection).to receive(:get) do |&block|
        call_count += 1
        block&.call(call_count == 1 ? request : terminal_request)
        simulate_redirect_hops.call(terminal_url)
        raise Faraday::FollowRedirects::RedirectLimitReached, 'too many redirects'
      end

      expect { execute }.to raise_error(Faraday::FollowRedirects::RedirectLimitReached, /too many redirects/)
      expect(connection).to have_received(:get).twice
      expect(budget).to have_received(:consume!).once
    end

    it 'raises without retry when no redirect hop was recorded', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(connection).to receive(:get) do |&block|
        block&.call(request)
        raise Faraday::FollowRedirects::RedirectLimitReached, 'too many redirects'
      end

      expect { execute }.to raise_error(Faraday::FollowRedirects::RedirectLimitReached, /too many redirects/)
      expect(connection).to have_received(:get).once
    end
  end

  describe described_class::PeerIpValidator do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:mock_socket) { instance_double(IPSocket, peeraddr: ['AF_INET', 443, '93.184.216.34', '93.184.216.34']) }
    let(:mock_net_http) do
      Class.new do
        attr_accessor :address, :port

        def initialize
          @address = 'example.com'
          @port = 443
        end

        def use_ssl? = true

        def start
          yield self
        end
      end.new
    end

    before do
      mock_net_http.instance_variable_set(:@socket, mock_socket)
      described_class.install!(mock_net_http, policy:)
    end

    it 'validates the peer IP when HTTP connection starts', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      block_called = false
      mock_net_http.start { block_called = true }

      expect(policy).to have_received(:validate_remote_ip!).with(
        ip: '93.184.216.34',
        url: Html2rss::Url.from_absolute('https://example.com')
      )
      expect(block_called).to be true
    end

    it 'aborts execution if peer IP validation fails' do # rubocop:disable RSpec/ExampleLength
      allow(policy).to receive(:validate_remote_ip!).and_raise(
        Html2rss::RequestService::PrivateNetworkDenied, 'Private network target denied'
      )

      expect do
        mock_net_http.start { raise 'should not be reached' }
      end.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, 'Private network target denied')
    end
  end

  describe described_class::StreamingBodyMiddleware do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:middleware_response) { middleware.call(request_env) }

    let(:request_options) do
      Faraday::RequestOptions.new(
        context: {
          described_class::STREAM_BUFFER_KEY => compressed_body
        }
      )
    end
    let(:request_env) do
      Faraday::Env.from(
        method: :get,
        request: request_options,
        request_headers: Faraday::Utils::Headers.new,
        url: Addressable::URI.parse('https://example.com')
      )
    end
    let(:response_env) do
      Faraday::Env.from(
        request: request_options,
        status: 200,
        response_headers: Faraday::Utils::Headers.new('Content-Encoding' => 'gzip'),
        response_body: +''
      )
    end
    let(:app) do
      Class.new do
        define_method(:initialize) { |response| @response = response }
        define_method(:call) { |_env| @response }
      end.new(Faraday::Response.new(response_env))
    end
    let(:middleware) { Faraday::Gzip::Middleware.new(described_class.new(app)) }
    let(:compressed_body) do
      StringIO.new.tap do |io|
        Zlib::GzipWriter.wrap(io) { |gzip| gzip.write('<html></html>') }
      end.string
    end

    it 'restores buffered streamed bytes before gzip decoding' do
      expect(middleware_response.body).to eq('<html></html>')
    end
  end
end
