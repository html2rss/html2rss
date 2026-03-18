# frozen_string_literal: true

require 'spec_helper'

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
  let(:request) { instance_double(Faraday::Request, options: request_options) }
  let(:response_env) { instance_double(Faraday::Env, url: Addressable::URI.parse('https://example.com')) }
  let(:response) do
    instance_double(
      Faraday::Response,
      body: '<html></html>',
      headers: { 'content-type' => 'text/html' },
      env: response_env,
      status: 200
    )
  end

  before do
    allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)
    allow(connection).to receive(:get).and_yield(request).and_return(response)
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
    expect(result).to be_a(Html2rss::RequestService::Response)
  end
end
