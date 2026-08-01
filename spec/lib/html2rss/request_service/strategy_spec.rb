# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Strategy do
  subject(:instance) { described_class.new(ctx) }

  let(:url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }
  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      validate_request!: nil,
      max_decompressed_bytes: 1_000_000
    )
  end
  let(:budget) { instance_double(Html2rss::RequestService::Budget, consume!: nil, remaining_timeout_seconds: nil) }
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
end
