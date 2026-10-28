# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline::AutoFallback do
  describe '::NON_FALLBACK_ERRORS' do
    it 'includes RequestService::RedirectLimitReached' do
      expect(described_class::NON_FALLBACK_ERRORS)
        .to include(Html2rss::RequestService::RedirectLimitReached)
    end

    it 'does not abort auto when default strategy reports an unsupported content type' do
      expect(described_class::NON_FALLBACK_ERRORS)
        .not_to include(Html2rss::RequestService::UnsupportedResponseContentType)
    end
  end

  describe '::TERMINAL_TRANSPORT_ERRORS' do
    it 'names the transport failures preserved across zero-item hops', :aggregate_failures do
      expect(described_class::TERMINAL_TRANSPORT_ERRORS).to include(
        Html2rss::RequestService::RequestTimedOut,
        Html2rss::RequestService::BlockedSurfaceDetected,
        Html2rss::RequestService::ConnectionFailed
      )
    end
  end

  describe Html2rss::FeedPipeline::AutoFallback::AttemptState do
    subject(:state) { described_class.new }

    it 'keeps RequestTimedOut after a later hop records zero items', :aggregate_failures do
      timed_out = Html2rss::RequestService::RequestTimedOut.new('timed out')
      state.record_error(strategy: :default, error: timed_out)
      state.record_items(strategy: :botasaurus, items_count: 0)

      expect(state.last_error).to be_nil
      expect(state.terminal_transport_error).to eq(timed_out)
    end

    it 'keeps BlockedSurfaceDetected after a later hop records zero items', :aggregate_failures do
      blocked = Html2rss::RequestService::BlockedSurfaceDetected.new('Blocked surface detected')
      state.record_error(strategy: :default, error: blocked)
      state.record_items(strategy: :botasaurus, items_count: 0)

      expect(state.last_error).to be_nil
      expect(state.terminal_transport_error).to eq(blocked)
    end

    it 'records transport metadata for an Html2rss::Error subclass' do
      error = Class.new(Html2rss::Error).new('plain')
      error.transport_meta = { 'error_category' => 'denied' }
      state.record_error(strategy: :default, error:, elapsed_ms: 12)

      expect(state.attempts.last).to include(transport_meta: { 'error_category' => 'denied' }, elapsed_ms: 12)
    end

    it 'remembers a non-terminal error without storing it as terminal transport' do
      error = RuntimeError.new('boom')
      state.record_error(strategy: :default, error:)

      expect(state).to have_attributes(last_error: error, terminal_transport_error: nil)
    end

    it 'keeps a subclass of a terminal transport error' do
      error = Class.new(Html2rss::RequestService::RequestTimedOut).new('timed out')
      state.record_error(strategy: :default, error:)

      expect(state.terminal_transport_error).to eq(error)
    end

    it 're-raises a non-Html2rss error without attaching attempts' do
      error = RuntimeError.new('boom')
      state.record_error(strategy: :default, error:)

      expect { state.raise_failure! }.to raise_error(error)
    end

    it 'raises NoFeedItemsExtracted when nothing failed' do
      expect { state.raise_failure! }.to raise_error(Html2rss::NoFeedItemsExtracted)
    end

    it 'classifies the last response on an empty failure', :aggregate_failures do
      response = instance_double(Html2rss::RequestService::Response, url: :listing)
      state.remember_response(response)
      allow(Html2rss::PageRecon).to receive(:surface_category_for).and_return(:app_shell)

      expect { state.raise_failure! }.to raise_error(have_attributes(surface_category: :app_shell))
      expect(Html2rss::PageRecon).to have_received(:surface_category_for).with(response:, url: :listing)
    end
  end

  describe 'transport failure preservation through the auto chain' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:build_response) do
      lambda do |body:, url: 'https://example.com/news', headers: { 'content-type' => 'text/html' }|
        Html2rss::RequestService::Response.new(
          body:,
          url: Html2rss::Url.from_absolute(url),
          headers:,
          status: 200
        )
      end
    end
    let(:base_config) do
      {
        channel: { url: 'https://example.com/news', title: 'Example News' },
        selectors: {
          items: { selector: 'article' },
          title: { selector: 'h1' }
        }
      }
    end
    let(:config) { base_config.merge(strategy: :auto, request: { max_requests: 3 }) }
    let(:pipeline) { Html2rss::FeedPipeline.new(config) }
    let(:empty_response) { build_response.call(body: '<html><body><div>empty</div></body></html>') }
    let(:item_response) do
      build_response.call(body: '<html><body><article><h1>bota</h1></article></body></html>')
    end
    let(:strategy_results) { {} }

    before do
      allow(Html2rss::Log).to receive(:info)
      allow(Html2rss::Log).to receive(:warn)
      allow(Html2rss::Log).to receive(:debug)
      allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
        ctx.budget.consume!
        result = strategy_results.fetch(strategy)
        raise result if result.is_a?(Exception)

        result
      end
    end

    context 'when default times out and botasaurus extracts zero items' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: Html2rss::RequestService::RequestTimedOut.new('timed out'),
          botasaurus: empty_response
        }
      end

      it 'logs the timeout before the next strategy', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RequestTimedOut)
        expect(Html2rss::Log).to have_received(:info).with(a_string_including('auto fallback default -> botasaurus'))
      end

      # rubocop:disable-next RSpec/ExampleLength -- attempts for both hops
      it 're-raises RequestTimedOut with both attempts attached', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RequestTimedOut) do |error|
          expect(error.attempts).to include(
            hash_including(
              strategy: :default,
              error_class: 'Html2rss::RequestService::RequestTimedOut',
              elapsed_ms: be < 10_000
            ),
            hash_including(strategy: :botasaurus, items_count: 0, error_class: nil, elapsed_ms: be < 10_000)
          )
        end
      end
    end

    context 'when default connection fails and botasaurus extracts zero items' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: Html2rss::RequestService::ConnectionFailed.new('connection refused'),
          botasaurus: empty_response
        }
      end

      # rubocop:disable-next RSpec/ExampleLength -- attempts for both hops
      it 're-raises ConnectionFailed with both attempts attached', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::ConnectionFailed) do |error|
          expect(error.attempts).to include(
            hash_including(
              strategy: :default,
              error_class: 'Html2rss::RequestService::ConnectionFailed',
              elapsed_ms: be < 10_000
            ),
            hash_including(strategy: :botasaurus, items_count: 0, error_class: nil, elapsed_ms: be < 10_000)
          )
        end
      end
    end

    context 'when default times out and botasaurus extracts items' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: Html2rss::RequestService::RequestTimedOut.new('timed out'),
          botasaurus: item_response
        }
      end

      it 'succeeds with the later hop items' do
        expect(pipeline.to_result.to_rss.items.map(&:title)).to eq(['bota'])
      end

      it 'passes the effective URL into the request session' do
        allow(pipeline).to receive(:request_session_for).and_call_original
        pipeline.to_result

        expect(pipeline).to have_received(:request_session_for).with(
          kind_of(Html2rss::Config), hash_including(scrape_url: 'https://example.com/news')
        ).at_least(:once)
      end
    end

    context 'when every hop extracts zero items with no terminal transport error' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: empty_response,
          botasaurus: empty_response
        }
      end

      it 'raises NoFeedItemsExtracted' do
        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted)
      end

      it 'logs the fallback before the next strategy' do
        pipeline.to_result
      rescue Html2rss::NoFeedItemsExtracted
        expect(Html2rss::Log).to have_received(:info).with(
          a_string_including('auto_fallback.zero_items').and(a_string_including('botasaurus'))
        )
      end
    end

    context 'when the last strategy raises' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: empty_response,
          botasaurus: RuntimeError.new('late')
        }
      end

      it 'does not log a next hop after the last strategy', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(RuntimeError, 'late')
        expect(Html2rss::Log).not_to have_received(:warn).with(a_string_including('botasaurus ->'))
      end
    end

    context 'when the session cannot be opened' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before { allow(pipeline).to receive(:request_session_for).and_raise(RuntimeError, 'no session') }

      it 'does not log a fallback for a missing session' do
        expect { pipeline.to_result }.to raise_error(RuntimeError, 'no session')
      end
    end

    context 'when default raises a non-fallback error' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:strategy_results) do
        {
          default: Html2rss::RequestService::InvalidUrl.new('bad url'),
          botasaurus: item_response
        }
      end

      it 'aborts before the next strategy', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::InvalidUrl) do |error|
          expect(error.attempts).to include(hash_including(strategy: :default, elapsed_ms: be < 10_000))
        end
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end
    end
  end
end
