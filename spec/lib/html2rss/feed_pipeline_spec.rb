# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline do
  let(:build_response) do
    lambda do |body:, url: 'https://example.com/news'|
      Html2rss::RequestService::Response.new(
        body:,
        url: Html2rss::Url.from_absolute(url),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end
  end

  let(:stub_first_strategy_success) do
    lambda do |response|
      allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
        ctx.budget.consume!
        raise "Unexpected strategy #{strategy}" unless strategy == :faraday

        response
      end
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

  describe '#to_result' do
    context 'when strategy is non-auto' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) { base_config.merge(strategy: :faraday) }
      let(:pipeline) { described_class.new(config) }
      let(:response) do
        build_response.call(body: '<html><body><article><h1>faraday</h1></article></body></html>')
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :faraday

          response
        end
      end

      it 'runs the configured strategy path and does not invoke auto fallback', :aggregate_failures do
        result = pipeline.to_result
        rss = result.to_rss

        expect(rss.items.map(&:title)).to eq(['faraday'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end
    end

    context 'when strategy is auto' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) { base_config.merge(strategy: :auto, request: { max_requests: 3 }) }
      let(:pipeline) { described_class.new(config) }
      let(:empty_response) do
        build_response.call(body: '<html><body><div>empty</div></body></html>')
      end
      let(:item_response) do
        build_response.call(body: '<html><body><article><h1>bota</h1></article></body></html>')
      end
      let(:strategy_results) do
        {
          faraday: empty_response,
          botasaurus: item_response
        }
      end

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

      it 'uses auto fallback chain when the first strategy yields zero items', :aggregate_failures do
        result = pipeline.to_result
        rss = result.to_rss

        expect(rss.items.map(&:title)).to eq(['bota'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
      end

      it 'logs fallback transition when first strategy returns zero items' do
        pipeline.to_result

        expect(Html2rss::Log).to have_received(:info).with(
          /auto fallback faraday -> botasaurus after zero extracted items/
        ).once
      end

      it 'logs selected strategy when fallback succeeds after retries' do
        pipeline.to_result

        expect(Html2rss::Log).to have_received(:info).with(
          /auto selected strategy=botasaurus after attempts=2/
        ).once
      end

      it 'does not call fallback strategy when first strategy succeeds', :aggregate_failures do
        stub_first_strategy_success.call(item_response)

        pipeline.to_result

        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end

      it 'does not emit fallback info when first strategy succeeds' do
        stub_first_strategy_success.call(item_response)

        pipeline.to_result

        expect(Html2rss::Log).not_to have_received(:info)
      end

      it 'raises when botasaurus is not configured (no browserless hop)', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        strategy_results[:botasaurus] = Html2rss::RequestService::BotasaurusConfigurationError.new('missing url')

        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
          expect(error.attempts).to include(
            hash_including(strategy: :botasaurus, error_class: 'Html2rss::RequestService::BotasaurusConfigurationError')
          )
        end
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :browserless)
      end

      context 'when first strategy fails but fallback strategy succeeds' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        let(:strategy_results) do
          {
            faraday: Html2rss::RequestService::RequestTimedOut.new('timed out'),
            botasaurus: item_response
          }
        end

        before { pipeline.to_result }

        it 'logs timeout fallback at info with host and budget context' do
          expect(Html2rss::Log).to have_received(:info).with(
            /auto fallback faraday -> botasaurus after timeout=Html2rss::RequestService::RequestTimedOut.*host=/
          ).once
        end

        it 'keeps full error details in debug logs' do
          expect(Html2rss::Log).to have_received(:debug).with(
            /strategy=faraday error=Html2rss::RequestService::RequestTimedOut: timed out/
          ).once
        end
      end

      # rubocop:disable RSpec/ExampleLength
      it 'lets Strategy enforce exhausted time budget on later auto attempts', :aggregate_failures do
        t = 0.0
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { t }
        allow(Html2rss::RequestService).to receive(:execute).and_call_original
        allow(Html2rss::RequestService).to receive(:execute).with(anything, strategy: :faraday) do
          t += 1.5 # advance time to exceed the 1s budget
          raise Html2rss::RequestService::RequestTimedOut, 'timed out'
        end

        pipeline = described_class.new(base_config.merge(strategy: :auto, request: { total_timeout_seconds: 1 }))
        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
          expect(error.attempts.map { |attempt| attempt[:strategy] }).to include(:faraday, :botasaurus)
          expect(error.attempts).to include(
            hash_including(strategy: :botasaurus, error_class: 'Html2rss::RequestService::RequestTimedOut')
          )
        end
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
      end
      # rubocop:enable RSpec/ExampleLength
    end

    context 'when fixed strategy uses browserless preload' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        base_config.merge(
          strategy: :browserless,
          request: { browserless: { preload: { wait_after_ms: 500 } } }
        )
      end
      let(:pipeline) { described_class.new(config) }
      let(:response) do
        build_response.call(body: '<html><body><article><h1>browser</h1></article></body></html>')
      end
      let(:captured_budget) { [] }

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          captured_budget << {
            remaining_requests: ctx.budget.remaining_requests,
            remaining_interactions: ctx.budget.remaining_interactions
          }
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :browserless

          response
        end
      end

      # rubocop:disable RSpec/ExampleLength
      it 'locks the executed budget to RuntimePolicy.budget_for', :aggregate_failures do
        expected = Html2rss::FeedPipeline::RuntimePolicy.budget_for(
          Html2rss::Config.from_hash(config)
        )

        result = pipeline.to_result
        rss = result.to_rss

        expect(rss.items.map(&:title)).to eq(['browser'])
        expect(captured_budget).to eq(
          [{
            remaining_requests: expected.remaining_requests,
            remaining_interactions: expected.remaining_interactions
          }]
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    context 'with selector pagination strategies' do
      # rubocop:disable RSpec/ExampleLength
      it 'paginates using url_template strategy and content-stops on empty page', :aggregate_failures do
        p1 = build_response.call(body: '<html><body><article><h1>Item 1</h1></article></body></html>', url: 'https://example.com/news')
        p2 = build_response.call(body: '<html><body><article><h1>Item 2</h1></article></body></html>', url: 'https://example.com/news?page=2')
        p3 = build_response.call(body: '<html><body><div>No items</div></body></html>', url: 'https://example.com/news?page=3')
        responses = { 'https://example.com/news' => p1, 'https://example.com/news?page=2' => p2, 'https://example.com/news?page=3' => p3 }

        config = base_config.merge(
          strategy: :faraday,
          selectors: base_config[:selectors].merge(
            items: { selector: 'article', pagination: { strategy: 'url_template', param: 'page', max_pages: 5 } }
          )
        )

        allow(Html2rss::RequestService).to receive(:execute) do |ctx, **|
          ctx.budget.consume!
          responses.fetch(ctx.url.to_s)
        end

        rss = described_class.new(config).to_result.to_rss
        expect(rss.items.map(&:title)).to eq(['Item 1', 'Item 2'])
        expect(Html2rss::RequestService).to have_received(:execute).exactly(3).times
      end
      # rubocop:enable RSpec/ExampleLength
    end

    # rubocop:disable RSpec/ExampleLength -- inline config + duplicate HTML fixture
    it 'reports dedup_dropped on status after pipeline deduplication', :aggregate_failures do
      config = base_config.merge(
        strategy: :faraday,
        selectors: base_config[:selectors].merge(
          url: { selector: 'a', extractor: 'href' },
          id: { selector: 'a', extractor: 'href' }
        )
      )
      response = build_response.call(
        body: <<~HTML,
          <html><body>
            <article><a href="https://example.com/news/dup"><h1>First</h1></a></article>
            <article><a href="https://example.com/news/dup"><h1>Second</h1></a></article>
          </body></html>
        HTML
        url: 'https://example.com/news'
      )
      stub_first_strategy_success.call(response)

      result = described_class.new(config).to_result

      expect(result.status.dedup_dropped).to eq(1)
      expect(result.status.selected_strategy).to be_nil
      expect(result.status.attempt_count).to eq(0)
      expect(result.to_rss.items.size).to eq(1)
    end
    # rubocop:enable RSpec/ExampleLength

    context 'when strategy is auto and fallback succeeds' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) { base_config.merge(strategy: :auto, request: { max_requests: 3 }) }
      let(:empty_response) do
        build_response.call(body: '<html><body><div>empty</div></body></html>')
      end
      let(:item_response) do
        build_response.call(body: '<html><body><article><h1>bota</h1></article></body></html>')
      end

      before do
        allow(Html2rss::Log).to receive(:info)
        allow(Html2rss::Log).to receive(:warn)
        allow(Html2rss::Log).to receive(:debug)
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          strategy == :faraday ? empty_response : item_response
        end
      end

      it 'puts selected_strategy, attempt_count, and strategy_attempts on status', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.new(config).to_result

        expect(result.status.selected_strategy).to eq(:botasaurus)
        expect(result.status.attempt_count).to eq(2)
        expect(result.status.strategy_attempts).to eq(
          [
            { strategy: :faraday, items_count: 0, error_class: nil },
            { strategy: :botasaurus, items_count: 1, error_class: nil }
          ]
        )
        expect(result.status.to_h).to include(
          selected_strategy: :botasaurus,
          attempt_count: 2,
          strategy_attempts: result.status.strategy_attempts
        )
        expect(result.status.to_generator_comment).not_to include('botasaurus')
      end
    end
  end
end
