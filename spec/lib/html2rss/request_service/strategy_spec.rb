# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Strategy do
  subject(:instance) { described_class.new(ctx) }

  let(:url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }
  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      validate_request!: nil,
      max_decompressed_bytes: 1_000_000,
      total_timeout_seconds: 30
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
    instance_double(
      Html2rss::RequestService::Context,
      url:,
      origin_url: url,
      relation: :channel,
      policy:,
      budget:
    )
  end

  describe '#execute' do
    it 'requires subclasses to implement #fetch' do
      expect { instance.execute }.to raise_error(NotImplementedError, /Subclass must implement #fetch/)
    end
  end

  describe 'guarded execute contract' do
    subject(:execute) { adapter.new(ctx).execute }

    let(:adapter) do
      Class.new(described_class) do
        private

        def fetch
          Html2rss::RequestService::Response.new(
            body: '<html></html>',
            headers: {},
            url: ctx.url,
            status: 200
          )
        end
      end
    end

    it 'consumes budget and validates policy before fetch so adapters cannot skip preflight',
       :aggregate_failures do
      execute

      expect(budget).to have_received(:consume!)
      expect(policy).to have_received(:validate_request!).with(url:, origin_url: url, relation: :channel)
    end

    it 'runs ResponseGuard postflight on the fetched body' do
      allow(Html2rss::RequestService::ResponseGuard).to receive(:new).and_call_original

      execute

      expect(Html2rss::RequestService::ResponseGuard).to have_received(:new).with(policy:)
    end
  end

  describe 'timeout logging' do
    let(:adapter) do
      Class.new(described_class) do
        private

        def fetch
          raise Faraday::TimeoutError, 'execution expired for https://secret.example/path?token=abc'
        end
      end
    end

    before do
      allow(Html2rss::Log).to receive(:info)
      allow(Html2rss::Log).to receive(:debug)
    end

    # rubocop:disable RSpec/ExampleLength -- structured info fields + debug message redaction
    it 'keeps transport details out of info logs', :aggregate_failures do
      expect { adapter.new(ctx).execute }.to raise_error(Html2rss::RequestService::RequestTimedOut)

      expect(Html2rss::Log).to have_received(:info) do |message|
        expect(message).to include('request timeout')
        expect(message).to include('host=example.com')
        expect(message).to include('reason=transport')
        expect(message).not_to include('token=abc')
        expect(message).not_to include('secret.example')
      end
      expect(Html2rss::Log).to have_received(:debug).with(
        a_string_matching(/transport timeout message=.*token=abc/)
      )
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
