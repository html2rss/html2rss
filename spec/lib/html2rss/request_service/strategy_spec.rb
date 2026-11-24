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
      remaining_timeout_seconds: 30.0,
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
      advertisement: nil,
      policy:,
      budget:
    )
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
      expect(policy).to have_received(:validate_request!).with(url:, origin_url: url, relation: :channel,
                                                               advertisement: nil)
    end

    it 'hands the context feed advertisement to policy validation' do
      advertisement = Html2rss::RequestService::FeedAdvertisement.from_document(Nokogiri::HTML('<head></head>'),
                                                                                page_url: url)
      allow(ctx).to receive(:advertisement).and_return(advertisement)

      execute

      expect(policy).to have_received(:validate_request!).with(hash_including(advertisement:))
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers -- shared ctx doubles plus per-context body
  describe 'postflight body guard' do
    subject(:execute) { adapter.new(ctx).execute }

    let(:max_bytes) { 1_000 }
    let(:body) { '<html></html>' }
    let(:adapter) do
      fetched = body
      Class.new(described_class) do
        private

        define_method(:fetch) do
          Html2rss::RequestService::Response.new(body: fetched, headers: {}, url: ctx.url, status: 200)
        end
      end
    end
    let(:blocked_body) do
      Pathname(__dir__).join('../../../fixtures/challenge/cloudflare_interstitial.html').expand_path.read
    end

    before { allow(policy).to receive(:max_decompressed_bytes).and_return(max_bytes) }

    context 'with a body above the decompressed limit' do
      let(:body) { 'x' * 1_001 }

      it 'raises ResponseTooLarge' do
        expect { execute }.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 1000 bytes')
      end
    end

    context 'with a body at the limit' do
      let(:body) { 'x' * 1_000 }

      it('accepts it') { expect { execute }.not_to raise_error }
    end

    context 'with a Cloudflare interstitial body' do
      let(:body) { blocked_body }

      it 'raises BlockedSurfaceDetected' do # rubocop:disable RSpec/ExampleLength
        expect { execute }.to raise_error(
          Html2rss::RequestService::BlockedSurfaceDetected,
          'Blocked surface detected: Cloudflare anti-bot interstitial page. ' \
          'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, or run from an ' \
          'environment that can complete anti-bot checks.'
        )
      end
    end

    context 'with an nginx 403 block page' do
      let(:body) do
        '<html><head><title>403 Forbidden</title></head><body>' \
          '<center><h1>403 Forbidden</h1></center><hr><center>nginx</center></body></html>'
      end

      it 'raises BlockedSurfaceDetected' do
        expect { execute }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected, /403 Forbidden/)
      end
    end

    context 'when the adapter guards bodies itself' do
      let(:body) { blocked_body }
      let(:adapter) do
        fetched = body
        Class.new(described_class) do
          private

          def skip_postflight? = true

          define_method(:fetch) do
            Html2rss::RequestService::Response.new(body: fetched, headers: {}, url: ctx.url, status: 200)
          end
        end
      end

      it('skips the postflight scan') { expect { execute }.not_to raise_error }
    end

    context 'with a nil body' do
      let(:body) { nil }

      it('treats it as empty') { expect { execute }.not_to raise_error }
    end

    context 'with only one interstitial marker' do
      let(:body) { '<html><title>Just a moment...</title></html>' }

      it('accepts it') { expect { execute }.not_to raise_error }
    end
  end

  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe 'contract errors' do
    let(:adapter) do
      Class.new(described_class) do
        private

        def fetch
          raise Html2rss::RequestService::Context::InvalidError, 'bug'
        end
      end
    end

    it 're-raises a ContractError untouched' do
      expect { adapter.new(ctx).execute }.to raise_error(Html2rss::RequestService::Context::InvalidError, 'bug')
    end
  end

  describe 'timeout logging' do
    let(:adapter) do
      Class.new(described_class) do
        private

        def fetch
          raise Timeout::Error, 'execution expired for https://secret.example/path?token=abc'
        end
      end
    end

    before do
      allow(Html2rss::Log).to receive(:info)
      allow(Html2rss::Log).to receive(:debug)
    end

    # rubocop:disable-next RSpec/ExampleLength -- structured info fields + debug message redaction
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
  end
end
