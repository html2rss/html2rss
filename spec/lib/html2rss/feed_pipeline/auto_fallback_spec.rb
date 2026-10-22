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
        Html2rss::RequestService::BlockedSurfaceDetected
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

      # rubocop:disable-next RSpec/ExampleLength -- attempts for both hops
      it 're-raises RequestTimedOut with both attempts attached', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RequestTimedOut) do |error|
          expect(error.attempts).to include(
            hash_including(strategy: :default, error_class: 'Html2rss::RequestService::RequestTimedOut'),
            hash_including(strategy: :botasaurus, items_count: 0, error_class: nil)
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
    end
  end
end
