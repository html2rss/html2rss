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

  describe '#to_rss' do
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
        rss = pipeline.to_rss

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
      let(:browserless_response) do
        build_response.call(body: '<html><body><article><h1>browser</h1></article></body></html>')
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
        rss = pipeline.to_rss

        expect(rss.items.map(&:title)).to eq(['bota'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
      end

      it 'logs fallback transition when first strategy returns zero items' do
        pipeline.to_rss

        expect(Html2rss::Log).to have_received(:info).with(
          /auto fallback faraday -> botasaurus after zero extracted items/
        ).once
      end

      it 'logs selected strategy when fallback succeeds after retries' do
        pipeline.to_rss

        expect(Html2rss::Log).to have_received(:info).with(
          /auto selected strategy=botasaurus after attempts=2/
        ).once
      end

      it 'does not call fallback strategy when first strategy succeeds', :aggregate_failures do
        stub_first_strategy_success.call(item_response)

        pipeline.to_rss

        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end

      it 'does not emit fallback info when first strategy succeeds' do
        stub_first_strategy_success.call(item_response)

        pipeline.to_rss

        expect(Html2rss::Log).not_to have_received(:info)
      end

      it 'continues auto fallback when botasaurus is not configured', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        strategy_results[:botasaurus] = Html2rss::RequestService::BotasaurusConfigurationError.new('missing url')
        strategy_results[:browserless] = browserless_response

        rss = pipeline.to_rss

        expect(rss.items.map(&:title)).to eq(['browser'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :browserless).once
      end

      context 'when first strategy fails but fallback strategy succeeds' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        let(:strategy_results) do
          {
            faraday: Html2rss::RequestService::RequestTimedOut.new('timed out'),
            botasaurus: item_response
          }
        end

        before { pipeline.to_rss }

        it 'warns with class-only detail' do
          expect(Html2rss::Log).to have_received(:warn).with(
            /auto fallback faraday -> botasaurus after error=Html2rss::RequestService::RequestTimedOut/
          ).once
        end

        it 'keeps full error details in debug logs' do
          expect(Html2rss::Log).to have_received(:debug).with(
            /strategy=faraday error=Html2rss::RequestService::RequestTimedOut: timed out/
          ).once
        end
      end
    end
  end
end
