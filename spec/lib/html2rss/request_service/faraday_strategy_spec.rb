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
      validate_redirect!: nil
    )
  end
  let(:budget) { instance_double(Html2rss::RequestService::Budget, consume!: nil) }
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
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0, 112.0)
    allow(connection).to receive(:get) do |&block|
      call_count += 1
      block&.call(call_count == 1 ? request : retry_request)
      call_count == 1 ? empty_redirected_response : recovered_response
    end

    result = execute

    expect(budget).to have_received(:consume!).twice
    expect(policy).to have_received(:validate_request!).twice
    expect(connection).to have_received(:get).twice
    expect(retry_request_options.timeout).to eq(18)
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
