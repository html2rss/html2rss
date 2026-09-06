# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline do
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

  let(:stub_first_strategy_success) do
    lambda do |response|
      allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
        ctx.budget.consume!
        raise "Unexpected strategy #{strategy}" unless strategy == :default

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
      let(:config) { base_config.merge(strategy: :default) }
      let(:pipeline) { described_class.new(config) }
      let(:response) do
        build_response.call(body: '<html><body><article><h1>default</h1></article></body></html>')
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :default

          response
        end
      end

      it 'runs the configured strategy path and does not invoke auto fallback', :aggregate_failures do
        result = pipeline.to_result
        rss = result.to_rss

        expect(rss.items.map(&:title)).to eq(['default'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end
    end

    context 'when strategy is non-auto with auto_source yielding zero articles' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        {
          strategy: :default,
          channel: { url: 'https://example.com/news', title: 'Example News' },
          auto_source: {}
        }
      end
      let(:pipeline) { described_class.new(config) }
      let(:empty_response) { build_response.call(body: '<html><body><div>empty</div></body></html>') }

      before do
        allow(Html2rss::RequestService).to receive(:execute).and_return(empty_response)
      end

      it 'raises NoFeedItemsExtracted at the pipeline boundary', :aggregate_failures do
        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
          expect(error.attempts).to eq([{ strategy: :default, items_count: 0, error_class: nil }])
          expect(error.surface_category).to eq(:unsupported_surface)
        end
      end

      context 'when the empty page looks like an app shell' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:empty_response) do
          build_response.call(
            body: '<html><body><div id="root"></div><script src="/assets/app.js"></script></body></html>'
          )
        end

        it 'appends the shared app-shell guidance', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
            expect(error.surface_category).to eq(:app_shell)
            expect(error.message).to include('app-shell surface detected')
            expect(error.message).to include('BOTASAURUS_SCRAPER_URL')
          end
        end
      end

      context 'when the empty page is a dense high-entropy hub' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:empty_response) do
          links = Array.new(Html2rss::AutoSource::Scraper::HIGH_ENTROPY_MIN_ANCHORS) do |index|
            %(<a href="/dating/pad-#{index}">Pad #{index} Extra Words</a>)
          end.join
          build_response.call(body: "<html><body>#{links}</body></html>")
        end

        it 'appends high-entropy listing-URL guidance', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
            expect(error.surface_category).to eq(:high_entropy_surface)
            expect(error.message).to include('high-entropy surface')
            expect(error.message).to include('listing/update URL')
          end
        end
      end
    end

    context 'when strategy is non-auto with selector-only yielding zero articles' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) { base_config.merge(strategy: :default) }
      let(:pipeline) { described_class.new(config) }
      let(:empty_response) { build_response.call(body: '<html><body><div>empty</div></body></html>') }

      before do
        allow(Html2rss::RequestService).to receive(:execute).and_return(empty_response)
      end

      it 'returns an empty result without raising' do
        expect(pipeline.to_result).to be_empty
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
          default: empty_response,
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
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
      end

      it 'logs fallback transition when first strategy returns zero items' do
        pipeline.to_result

        expect(Html2rss::Log).to have_received(:info).with(
          /auto fallback default -> botasaurus after zero extracted items/
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

        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end

      it 'does not emit fallback info when first strategy succeeds' do
        stub_first_strategy_success.call(item_response)

        pipeline.to_result

        expect(Html2rss::Log).not_to have_received(:info)
      end

      it 'raises when botasaurus is not configured after default failure', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        strategy_results[:botasaurus] = Html2rss::RequestService::BotasaurusConfigurationError.new('missing url')
        hint = Html2rss::RequestService::BotasaurusConfigurationError::EMPTY_FEED_HINT

        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
          expect(error.attempts).to include(
            hash_including(strategy: :botasaurus, error_class: 'Html2rss::RequestService::BotasaurusConfigurationError')
          )
          expect(error.message).to include(hint)
        end
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
      end

      context 'when every strategy yields an app-shell page' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:app_shell_response) do
          build_response.call(
            body: '<html><body><div id="root"></div><script src="/assets/app.js"></script></body></html>'
          )
        end
        let(:strategy_results) do
          {
            default: app_shell_response,
            botasaurus: app_shell_response
          }
        end
        let(:config) do
          {
            strategy: :auto,
            request: { max_requests: 3 },
            channel: { url: 'https://example.com/news', title: 'Example News' },
            auto_source: {}
          }
        end

        it 'raises NoFeedItemsExtracted with app-shell guidance', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
            expect(error.surface_category).to eq(:app_shell)
            expect(error.message).to include('app-shell surface detected')
          end
        end
      end

      context 'when default returns deterministic HTTP 404 Not Found' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:strategy_results) do
          {
            default: Html2rss::RequestService::Response.new(
              body: '<html><body><h1>404 Not Found</h1></body></html>',
              url: Html2rss::Url.from_absolute('https://example.com/news'),
              headers: { 'content-type' => 'text/html' },
              status: 404
            ),
            botasaurus: item_response
          }
        end

        # rubocop:disable-next RSpec/ExampleLength
        it 'aborts auto fallback immediately without attempting Botasaurus', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
            expect(error.attempts.size).to eq(1)
            expect(error.attempts.first[:strategy]).to eq(:default)
          end
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
          expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
        end
      end

      context 'when default raises RequestService::RedirectLimitReached' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:strategy_results) do
          {
            default: Html2rss::RequestService::RedirectLimitReached.new('redirect limit reached'),
            botasaurus: item_response
          }
        end

        it 'aborts immediately without attempting Botasaurus', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RedirectLimitReached)
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
          expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
        end
      end

      context 'when default raises UnsupportedResponseContentType' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:strategy_results) do
          {
            default: Html2rss::RequestService::UnsupportedResponseContentType.new(
              'Unsupported content type: application/octet-stream'
            ),
            botasaurus: item_response
          }
        end

        it 'falls back to Botasaurus instead of aborting auto', :aggregate_failures do
          rss = pipeline.to_result.to_rss

          expect(rss.items.map(&:title)).to eq(['bota'])
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
        end
      end

      context 'when default returns HTML labeled as octet-stream' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:strategy_results) do
          {
            default: build_response.call(
              body: '<html><body><article><h1>seznam</h1></article></body></html>',
              headers: { 'content-type' => 'application/octet-stream' }
            ),
            botasaurus: item_response
          }
        end

        it 'extracts default HTML without calling Botasaurus', :aggregate_failures do
          rss = pipeline.to_result.to_rss

          expect(rss.items.map(&:title)).to eq(['seznam'])
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
          expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
        end
      end

      context 'when default returns non-HTML octet-stream' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:strategy_results) do
          {
            default: build_response.call(
              body: "PK\x03\x04not-html",
              headers: { 'content-type' => 'application/octet-stream' }
            ),
            botasaurus: item_response
          }
        end

        it 'records the default error and uses Botasaurus', :aggregate_failures do
          rss = pipeline.to_result.to_rss

          expect(rss.items.map(&:title)).to eq(['bota'])
          expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
        end
      end

      context 'when first strategy fails but fallback strategy succeeds' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        let(:strategy_results) do
          {
            default: Html2rss::RequestService::RequestTimedOut.new('timed out'),
            botasaurus: item_response
          }
        end

        before { pipeline.to_result }

        it 'logs timeout fallback at info with host and budget context' do
          expect(Html2rss::Log).to have_received(:info).with(
            /auto fallback default -> botasaurus after timeout=Html2rss::RequestService::RequestTimedOut.*host=/
          ).once
        end

        it 'keeps full error details in debug logs' do
          expect(Html2rss::Log).to have_received(:debug).with(
            /strategy=default error=Html2rss::RequestService::RequestTimedOut: timed out/
          ).once
        end
      end

      # rubocop:disable RSpec/ExampleLength
      it 'lets Strategy enforce exhausted time budget on later auto attempts', :aggregate_failures do
        t = 0.0
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { t }
        allow(Html2rss::RequestService).to receive(:execute).and_call_original
        allow(Html2rss::RequestService).to receive(:execute).with(anything, strategy: :default) do
          t += 1.5 # advance time to exceed the 1s budget
          raise Html2rss::RequestService::RequestTimedOut, 'timed out'
        end

        pipeline = described_class.new(base_config.merge(strategy: :auto, request: { total_timeout_seconds: 1 }))
        expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
          expect(error.attempts.map { |attempt| attempt[:strategy] }).to include(:default, :botasaurus)
          expect(error.attempts).to include(
            hash_including(strategy: :botasaurus, error_class: 'Html2rss::RequestService::RequestTimedOut')
          )
        end
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
      end
    end

    context 'with selector pagination strategies' do
      it 'paginates using url_template strategy and content-stops on empty page', :aggregate_failures do
        p1 = build_response.call(body: '<html><body><article><h1>Item 1</h1></article></body></html>', url: 'https://example.com/news')
        p2 = build_response.call(body: '<html><body><article><h1>Item 2</h1></article></body></html>', url: 'https://example.com/news?page=2')
        p3 = build_response.call(body: '<html><body><div>No items</div></body></html>', url: 'https://example.com/news?page=3')
        responses = { 'https://example.com/news' => p1, 'https://example.com/news?page=2' => p2, 'https://example.com/news?page=3' => p3 }

        config = base_config.merge(
          strategy: :default,
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

    # rubocop:disable-next RSpec/ExampleLength -- inline config + duplicate HTML fixture
    it 'reports dedup_dropped on status after pipeline deduplication', :aggregate_failures do
      config = base_config.merge(
        strategy: :default,
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
          strategy == :default ? empty_response : item_response
        end
      end

      it 'puts selected_strategy, attempt_count, and strategy_attempts on status', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.new(config).to_result

        expect(result.status.selected_strategy).to eq(:botasaurus)
        expect(result.status.attempt_count).to eq(2)
        expect(result.status.strategy_attempts).to eq(
          [
            { strategy: :default, items_count: 0, error_class: nil },
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

    context 'when the entry URL is a direct syndication feed' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        {
          strategy: :default,
          channel: { url: 'https://example.com/feed.xml', title: 'Feed' },
          auto_source: {}
        }
      end
      let(:pipeline) { described_class.new(config) }
      let(:feed_response) do
        build_response.call(
          body: <<~XML,
            <?xml version="1.0"?>
            <rss version="2.0">
              <channel>
                <title>Feed</title>
                <link>https://example.com/</link>
                <description>d</description>
                <item>
                  <title>Direct item</title>
                  <link>https://example.com/posts/1</link>
                </item>
              </channel>
            </rss>
          XML
          url: 'https://example.com/feed.xml',
          headers: { 'content-type' => 'application/rss+xml' }
        )
      end

      before { stub_first_strategy_success.call(feed_response) }

      it 'parses syndication items without HTML AutoSource' do
        expect(pipeline.to_result.to_rss.items.map(&:title)).to eq(['Direct item'])
      end
    end
  end
end
