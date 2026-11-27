# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/auto_source_corpus'

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
        build_response.call(body: '<html><body><article><a href="/a"><h1>default</h1></a></article></body></html>')
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :default

          response
        end
      end

      it 'builds an outcome when params are omitted' do
        expect(pipeline.to_outcome.articles.map(&:title)).to eq(['default'])
      end

      it 'returns the outcome and the feed result', :aggregate_failures do
        outcome, result = pipeline.to_outcome_and_result

        expect(outcome.articles.map(&:title)).to eq(['default'])
        expect(outcome.scrape_target).to eq(Html2rss::FeedPipeline::ScrapeTarget.from_config(Html2rss::Config.from_hash(config)))
        expect(result.to_rss.items.map(&:title)).to eq(['default'])
      end

      it 'runs the configured strategy path and does not invoke auto fallback', :aggregate_failures do
        result = pipeline.to_result
        rss = result.to_rss

        expect(rss.items.map(&:title)).to eq(['default'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end
    end

    context 'when a selector item has no resolvable link' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) { base_config.merge(strategy: :default) }
      let(:result) { described_class.new(config).to_result }
      let(:response) do
        build_response.call(
          body: '<html><body><article><h1>no link</h1></article>' \
                '<article><a href="/a"><h1>linked</h1></a></article></body></html>'
        )
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, **|
          ctx.budget.consume!
          response
        end
      end

      it 'leaves it out of the RSS feed', :aggregate_failures do
        expect(result.to_rss.items.map(&:title)).to eq(['linked'])
        expect(result.to_rss.items.map(&:link)).to eq(['https://example.com/a'])
      end

      it 'leaves it out of the JSON Feed' do
        expect(result.to_json_feed[:items].map { _1[:title] }).to eq(['linked'])
      end
    end

    context 'when the config interpolates params' do
      let(:config) do
        base_config.merge(
          strategy: :default,
          channel: { url: 'https://example.com/%<section>s', title: 'Example News' },
          params: { section: 'news' }
        )
      end
      let(:pipeline) { described_class.new(config) }

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, **|
          ctx.budget.consume!
          build_response.call(body: '<html><body><article><a href="/a"><h1>scoped</h1></a></article></body></html>',
                              url: ctx.url.to_s)
        end
      end

      it 'fetches the interpolated channel URL' do
        pipeline.to_result

        expect(Html2rss::RequestService).to have_received(:execute).with(
          have_attributes(url: have_attributes(to_s: 'https://example.com/news')), strategy: :default
        )
      end

      it 'returns the interpolated outcome' do
        expect(pipeline.to_outcome.articles.map(&:title)).to eq(['scoped'])
      end

      it 'interpolates params into the paired result', :aggregate_failures do
        result = pipeline.to_outcome_and_result.last

        expect(result.to_rss.items.map(&:title)).to eq(['scoped'])
        expect(Html2rss::RequestService).to have_received(:execute).with(
          have_attributes(url: have_attributes(to_s: 'https://example.com/news')), strategy: :default
        )
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

        # rubocop:disable-next RSpec/ExampleLength -- category + honest app-shell hint assert
        it 'appends the shared app-shell guidance', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::NoFeedItemsExtracted) do |error|
            expect(error.surface_category).to eq(:app_shell)
            expect(error.message).to include('app-shell surface detected')
            expect(error.message).to include('browser strategy does not add extractable markup')
            expect(error.message).not_to include('BOTASAURUS_SCRAPER_URL')
          end
        end
      end

      context 'when the empty page is a dense high-entropy hub' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:empty_response) do
          links = Array.new(Html2rss::AutoSource::SurfaceCategory::HIGH_ENTROPY_MIN_ANCHORS) do |index|
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

    context 'when strategy is non-auto and the entry response is HTTP 404' do
      let(:pipeline) { described_class.new(config) }
      let(:not_found) do
        Html2rss::RequestService::Response.new(
          body: '<html><body><article><h1>Home</h1></article></body></html>',
          url: Html2rss::Url.from_absolute('https://example.com/news'),
          headers: { 'content-type' => 'text/html' },
          status: 404
        )
      end

      before { allow(Html2rss::RequestService).to receive(:execute).and_return(not_found) }

      context 'with selectors' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:config) { base_config.merge(strategy: :default) }

        it 'raises DeterministicHttpStatus instead of extracting', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::DeterministicHttpStatus) do |error|
            expect(error.status).to eq(404)
            expect(error.url.to_s).to eq('https://example.com/news')
          end
        end
      end

      context 'with auto_source' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:config) { { channel: { url: 'https://example.com/news' }, strategy: :default, auto_source: {} } }

        it 'raises DeterministicHttpStatus instead of NoFeedItemsExtracted' do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::DeterministicHttpStatus)
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
        build_response.call(body: '<html><body><article><a href="/a"><h1>bota</h1></a></article></body></html>')
      end
      let(:strategy_results) do
        {
          default: empty_response,
          botasaurus: item_response
        }
      end

      let(:extractions) { [] }
      let(:count_extractions) do
        lambda do
          allow(Html2rss::AutoSource).to receive(:new).and_wrap_original do |original, *args, **kwargs|
            original.call(*args, **kwargs).tap do |source|
              allow(source).to receive(:articles).and_wrap_original do |articles|
                extractions << source
                articles.call
              end
            end
          end
        end
      end
      let(:auto_source_config) do
        base_config.except(:selectors).merge(
          strategy: :auto, auto_source: { entry_resolution: { enabled: false } }, request: { max_requests: 8 }
        )
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
          a_string_including('"event_name":"auto_fallback.zero_items"')
            .and(a_string_including('after zero extracted items'))
        ).once
      end

      it 'logs selected strategy when fallback succeeds after retries' do
        pipeline.to_result

        expect(Html2rss::Log).to have_received(:info).with(
          a_string_including('"event_name":"auto_fallback.selected"')
            .and(a_string_including('auto selected strategy=botasaurus after attempts=2'))
        ).once
      end

      it 'does not call fallback strategy when first strategy succeeds', :aggregate_failures do
        stub_first_strategy_success.call(item_response)

        pipeline.to_result

        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end

      it 'extracts an auto_source feed request once', :aggregate_failures do
        stub_first_strategy_success.call(build_response.call(body: File.read('spec/fixtures/news_front_page.html')))
        count_extractions.call

        expect(described_class.new(auto_source_config).to_result.to_rss.items).not_to be_empty
        expect(extractions.size).to eq(1)
      end

      it 'does not extract a selectors-only feed request with AutoSource', :aggregate_failures do
        stub_first_strategy_success.call(item_response)
        count_extractions.call

        expect(described_class.new(config.merge(request: { max_requests: 8 })).to_result.to_rss.items.map(&:title))
          .to eq(['bota'])
        expect(extractions).to be_empty
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

      context 'when botasaurus raises a terminal RequestTimedOut' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:timed_out) do
          Html2rss::RequestService::RequestTimedOut.new('upstream timed out', timeout_phase: 'work').tap do |error|
            error.transport_meta = {
              'request_id' => 'req-timeout',
              'error_category' => 'timeout',
              'timeout_phase' => 'work'
            }
          end
        end
        let(:strategy_results) do
          {
            default: empty_response,
            botasaurus: timed_out
          }
        end

        it 're-raises RequestTimedOut instead of NoFeedItemsExtracted', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RequestTimedOut) do |error|
            expect(error.timeout_phase).to eq('work')
            expect(error.attempts.map { |attempt| attempt[:strategy] }).to eq(%i[default botasaurus])
            expect(error.transport_meta).to include('timeout_phase' => 'work')
          end
        end
      end

      context 'when botasaurus ends with a terminal challenge error' do # rubocop:disable RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
        let(:challenge_meta) do
          {
            'request_id' => 'req-challenge',
            'error_category' => 'challenge_block',
            'challenge' => { 'blocked' => true, 'detected' => true, 'marker' => 'Just a moment...' }
          }
        end
        let(:strategy_results) do
          blocked = Html2rss::RequestService::BlockedSurfaceDetected.new('Blocked surface detected')
          blocked.transport_meta = challenge_meta
          {
            default: empty_response,
            botasaurus: blocked
          }
        end

        # rubocop:disable-next RSpec/ExampleLength -- terminal error + attempts + transport_meta
        it 're-raises the terminal error with attempts and transport_meta', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected) do |error|
            expect(error.message).to include('Blocked surface detected')
            expect(error.attempts).to include(
              hash_including(strategy: :default, items_count: 0),
              hash_including(
                strategy: :botasaurus,
                error_class: 'Html2rss::RequestService::BlockedSurfaceDetected',
                transport_meta: challenge_meta
              )
            )
            expect(error.transport_meta).to eq(challenge_meta)
          end
        end
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

        # rubocop:disable-next RSpec/ExampleLength -- error payload + no next hop
        it 'raises DeterministicHttpStatus without attempting Botasaurus', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::DeterministicHttpStatus) do |error|
            expect(error.status).to eq(404)
            expect(error.diagnostics).to include(status: 404)
            expect(error.attempts).to include(hash_including(strategy: :default))
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

        # rubocop:disable-next RSpec/ExampleLength -- attempts + execute call expectations
        it 'aborts immediately without attempting Botasaurus', :aggregate_failures do
          expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RedirectLimitReached) do |error|
            expect(error.attempts).to include(
              hash_including(
                strategy: :default,
                error_class: 'Html2rss::RequestService::RedirectLimitReached',
                elapsed_ms: a_kind_of(Integer)
              )
            )
          end
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
              body: '<html><body><article><a href="/a"><h1>seznam</h1></a></article></body></html>',
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
            a_string_including('"event_name":"auto_fallback.timeout"')
              .and(a_string_including('RequestTimedOut'))
              .and(a_string_including('"host"'))
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
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :millisecond) { (t * 1000).to_i }
        allow(Html2rss::RequestService).to receive(:execute).and_call_original
        allow(Html2rss::RequestService).to receive(:execute).with(anything, strategy: :default) do
          t += 1.5 # advance time to exceed the 1s budget
          raise Html2rss::RequestService::RequestTimedOut, 'timed out'
        end

        pipeline = described_class.new(base_config.merge(strategy: :auto, request: { total_timeout_seconds: 1 }))
        expect { pipeline.to_result }.to raise_error(Html2rss::RequestService::RequestTimedOut) do |error|
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
        p1 = build_response.call(body: '<html><body><article><a href="/a"><h1>Item 1</h1></a></article></body></html>',
                                 url: 'https://example.com/news')
        p2 = build_response.call(body: '<html><body><article><a href="/b"><h1>Item 2</h1></a></article></body></html>',
                                 url: 'https://example.com/news?page=2')
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

    it 'tallies selector items dropped for having no URL as admission drops', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      config = Html2rss::Config.from_hash(
        { channel: { url: 'https://example.com/news' }, strategy: :default,
          selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a.missing' } } }
      )
      response = build_response.call(body: '<article><h1>A</h1></article><article><h1>B</h1></article>')
      session = instance_double(Html2rss::RequestSession, page_responses: [response])
      extraction = described_class.new({}).extract(config:, response:, request_session: session)

      expect(extraction.articles).to be_empty
      expect(extraction.admission_drops).to eq('missing_url' => 2)
    end

    it 'keeps paginating past an empty first page', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      config = Html2rss::Config.from_hash(
        { channel: { url: 'https://example.com/news' }, strategy: :default,
          selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a' } } }
      )
      page1 = build_response.call(body: '<div>No items</div>')
      page2 = build_response.call(body: '<article><h1>A</h1><a href="/a">a</a></article>',
                                  url: 'https://example.com/news?page=2')
      session = instance_double(Html2rss::RequestSession, page_responses: [page1, page2])
      extraction = described_class.new({}).extract(config:, response: page1, request_session: session)

      expect(extraction.articles.size).to eq(1)
      expect(extraction.admission_drops).to eq({})
    end

    it 'tallies the unlinked items of a page that ends pagination', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      config = Html2rss::Config.from_hash(
        { channel: { url: 'https://example.com/news' }, strategy: :default,
          selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a' } } }
      )
      page1 = build_response.call(body: '<article><h1>A</h1><a href="/a">a</a></article><article><h1>B</h1></article>')
      page2 = build_response.call(body: '<article><h1>C</h1></article>' * 3, url: 'https://example.com/news?page=2')
      session = instance_double(Html2rss::RequestSession, page_responses: [page1, page2])
      extraction = described_class.new({}).extract(config:, response: page1, request_session: session)

      expect(extraction.articles.size).to eq(1)
      expect(extraction.admission_drops).to eq('missing_url' => 4)
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength -- inline configs and HTML fixtures
    describe '#selector_articles' do
      let(:selector_config) do
        Html2rss::Config.from_hash(
          { channel: { url: 'https://example.com/news', time_zone: 'Europe/Berlin' }, strategy: :default,
            selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a' } } }
        )
      end
      let(:html) { '<article><h1>A</h1><a href="/a">a</a></article>' }
      let(:session) { instance_double(Html2rss::RequestSession) }

      it 'extracts nothing for a feed response', :aggregate_failures do
        response = build_response.call(body: '<rss version="2.0"><channel></channel></rss>',
                                       headers: { 'content-type' => 'application/rss+xml' })
        extraction = described_class.new({}).extract(config: selector_config, response:, request_session: session)

        expect(extraction.articles).to eq([])
        expect(extraction.admission_drops).to eq({})
      end

      it 'extracts nothing without selectors', :aggregate_failures do
        config = Html2rss::Config.from_hash({ channel: { url: 'https://example.com/news' }, auto_source: {} })
        allow(Html2rss::AutoSource).to receive(:new).and_return(
          instance_double(Html2rss::AutoSource, articles: [], admission_drops: {}, feed_channel: nil)
        )
        extraction = described_class.new({}).extract(config:, response: build_response.call(body: html),
                                                     request_session: session)

        expect(extraction.articles).to eq([])
      end

      it 'scopes auto-source by the channel language, the config override first', :aggregate_failures do
        config = Html2rss::Config.from_hash(
          { channel: { url: 'https://example.com/news', language: 'sv', time_zone: 'Europe/Berlin' }, auto_source: {} }
        )
        allow(Html2rss::AutoSource).to receive(:new).and_return(
          instance_double(Html2rss::AutoSource, articles: [], admission_drops: {}, feed_channel: nil)
        )
        described_class.new({}).extract(config:, response: build_response.call(body: '<html lang="de"></html>'),
                                        request_session: session)

        expect(Html2rss::AutoSource).to have_received(:new)
          .with(anything, anything, request_session: session, vocabulary: be(Html2rss::Vocabulary[:sv]),
                                    time_zone: 'Europe/Berlin')
      end

      it 'builds the selectors with the configured time zone' do
        response = build_response.call(body: html)
        allow(session).to receive(:page_responses).and_return([response])
        allow(Html2rss::Selectors).to receive(:new).and_call_original
        described_class.new({}).extract(config: selector_config, response:, request_session: session)

        expect(Html2rss::Selectors).to have_received(:new).with(response, selectors: selector_config.selectors,
                                                                          time_zone: 'Europe/Berlin',
                                                                          vocabulary: be(Html2rss::Vocabulary[nil]))
      end

      it 'reads every selector page under the language of the first response', :aggregate_failures do
        first = build_response.call(body: "<html lang=\"zh\"><body>#{html}</body></html>")
        second = build_response.call(body: '<article><h1>Page two</h1></article>')
        allow(session).to receive(:page_responses).and_return([first, second])
        allow(Html2rss::Selectors).to receive(:new).and_call_original
        described_class.new({}).extract(config: selector_config, response: first, request_session: session)

        expect(Html2rss::Selectors).to have_received(:new)
          .with(first, hash_including(vocabulary: be(Html2rss::Vocabulary[:zh])))
        expect(Html2rss::Selectors).to have_received(:new)
          .with(second, hash_including(vocabulary: be(Html2rss::Vocabulary[:zh])))
      end

      it 'lets the channel language override the page language of every selector page', :aggregate_failures do
        override = Html2rss::Config.from_hash(
          { channel: { url: 'https://example.com/news', language: 'zh-Hant' }, strategy: :default,
            selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a' } } }
        )
        first = build_response.call(body: html)
        allow(session).to receive(:page_responses).and_return([first])
        allow(Html2rss::Selectors).to receive(:new).and_call_original
        described_class.new({}).extract(config: override, response: first, request_session: session)

        expect(Html2rss::Selectors).to have_received(:new)
          .with(first, hash_including(vocabulary: be(Html2rss::Vocabulary[:zh])))
      end
    end

    describe '#collect_articles' do
      it 'sums selector and auto-source drops of the same reason', :aggregate_failures do
        config = Html2rss::Config.from_hash(
          { channel: { url: 'https://example.com/news' }, strategy: :default,
            selectors: { items: { selector: 'article' }, title: { selector: 'h1' }, url: { selector: 'a.missing' } },
            auto_source: {} }
        )
        response = build_response.call(body: '<article><h1>A</h1></article>')
        allow(Html2rss::AutoSource).to receive(:new).and_return(
          instance_double(Html2rss::AutoSource, articles: [], admission_drops: { 'missing_url' => 2, 'sponsored' => 1 },
                                                feed_channel: nil)
        )
        session = instance_double(Html2rss::RequestSession, page_responses: [response])
        extraction = described_class.new({}).extract(config:, response:, request_session: session)

        expect(extraction.admission_drops).to eq('missing_url' => 3, 'sponsored' => 1)
      end
    end

    # rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength

    it 'extracts the AutoSource admission drops and feed channel facts with the articles' do # rubocop:disable RSpec/ExampleLength
      facts = Html2rss::Syndication::ChannelFacts.new(author: 'Feed Author')
      source = instance_double(Html2rss::AutoSource, articles: [], admission_drops: { 'sponsored' => 1 },
                                                     feed_channel: facts)
      allow(Html2rss::AutoSource).to receive(:new).and_return(source)
      config = Html2rss::Config.from_hash({ channel: { url: 'https://example.com/news' }, auto_source: {} })

      expect(described_class.new({}).extract(config:, response: build_response.call(body: '<html></html>'),
                                             request_session: instance_double(Html2rss::RequestSession)))
        .to eq(Html2rss::FeedPipeline::Extracted.new(articles: [], dedup_dropped: 0,
                                                     admission_drops: { 'sponsored' => 1 }, feed_channel: facts))
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
            <article><a href="https://example.com/news/dup"><h1>Third</h1></a></article>
          </body></html>
        HTML
        url: 'https://example.com/news'
      )
      stub_first_strategy_success.call(response)

      result = described_class.new(config).to_result

      expect(result.status.dedup_dropped).to eq(2)
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
        build_response.call(body: '<html><body><article><a href="/a"><h1>bota</h1></a></article></body></html>')
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
        expect(result.status.strategy_attempts).to match(
          [
            hash_including(strategy: :default, items_count: 0, error_class: nil, elapsed_ms: a_kind_of(Integer)),
            hash_including(strategy: :botasaurus, items_count: 1, error_class: nil, elapsed_ms: a_kind_of(Integer))
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
            <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
              <channel>
                <title>Feed</title>
                <link>https://example.com/</link>
                <description>d</description>
                <itunes:author>Feed Author</itunes:author>
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

      it 'carries the feed author into the channel' do
        expect(pipeline.to_result.to_json_feed[:authors]).to eq([{ name: 'Feed Author' }])
      end
    end

    context 'when a syndication feed holds more items than the auto_source limit' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        {
          strategy: :default,
          channel: { url: 'https://example.com/feed.xml', title: 'Feed' },
          auto_source: { limit: 1 }
        }
      end
      let(:pipeline) { described_class.new(config) }
      let(:feed_response) do
        build_response.call(
          body: <<~XML,
            <?xml version="1.0"?>
            <rss version="2.0"><channel><title>Feed</title><link>https://example.com/</link><description>d</description>
              <item><title>First item</title><link>https://example.com/posts/1</link></item>
              <item><title>Second item</title><link>https://example.com/posts/2</link></item>
            </channel></rss>
          XML
          url: 'https://example.com/feed.xml',
          headers: { 'content-type' => 'application/rss+xml' }
        )
      end

      before { stub_first_strategy_success.call(feed_response) }

      it 'keeps only the first limit feed items' do
        expect(pipeline.to_result.to_rss.items.map(&:title)).to eq(['First item'])
      end
    end

    # A feed's files are untrusted: only an http(s) one becomes an enclosure, player, attachment or item URL.
    feed_entries = { 'a direct feed URL' => 'https://example.com/news/feed.xml',
                     'the page following its native feed' => 'https://example.com/news/' }
    {
      'RSS enclosure and media:content' => <<~XML,
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Feed</title>
          <link>https://example.com/</link><description>d</description>
          <item><title>Harbor council approves the new ferry schedule</title><link>https://example.com/posts/1</link>
            <enclosure url="javascript:alert(1)//a.mp3" type="audio/mpeg" length="5"/>
            <media:content url="data:audio/mpeg;base64,AAAA" medium="audio"/></item>
          <item><title>Harbor council episode without a page</title><guid isPermaLink="false">e2</guid>
            <enclosure url="ftp://example.com/a.mp3" type="audio/mpeg" length="5"/></item>
        </channel></rss>
      XML
      'Atom enclosure link' => <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Feed</title><id>https://example.com/</id>
          <updated>2026-01-01T00:00:00Z</updated>
          <entry><title>Harbor council approves the new ferry schedule</title><id>tag:example.com,2026:1</id><updated>2026-01-01T00:00:00Z</updated>
            <link href="https://example.com/posts/1"/>
            <link rel="enclosure" href="javascript:alert(1)//a.mp3" type="audio/mpeg" length="5"/></entry>
          <entry><title>Harbor council episode without a page</title><id>tag:example.com,2026:2</id><updated>2026-01-01T00:00:00Z</updated>
            <link rel="enclosure" href="data:audio/mpeg;base64,AAAA" type="audio/mpeg" length="5"/></entry>
        </feed>
      XML
    }.each do |declared, feed_body|
      context "when a feed declares only non-web files as #{declared}" do # rubocop:disable RSpec/MultipleMemoizedHelpers
        let(:feed_type) { feed_body.include?('<rss') ? 'application/rss+xml' : 'application/atom+xml' }
        let(:page_body) do
          '<html><head><title>News</title>' \
            "<link rel=\"alternate\" type=\"#{feed_type}\" href=\"/news/feed.xml\"></head>" \
            '<body><a href="/posts/1">Harbor council approves the new ferry schedule</a></body></html>'
        end
        let(:responses) do
          {
            'https://example.com/news/' => build_response.call(body: page_body, url: 'https://example.com/news/'),
            'https://example.com/news/feed.xml' =>
              build_response.call(body: feed_body, url: 'https://example.com/news/feed.xml',
                                  headers: { 'content-type' => feed_type })
          }
        end
        let(:result_for) do
          ->(url) { described_class.new({ strategy: :default, channel: { url: }, auto_source: {} }).to_result }
        end

        before do
          allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
            ctx.budget.consume!
            raise "Unexpected strategy #{strategy}" unless strategy == :default

            responses.fetch(ctx.url.to_s) { raise Html2rss::RequestService::ConnectionFailed, ctx.url.to_s }
          end
        end

        feed_entries.each do |entry, entry_url|
          it "ships no such file, player or item from #{entry}", :aggregate_failures do
            result = result_for.call(entry_url)
            rss = result.to_rss

            expect(rss.items.map(&:link)).to eq(['https://example.com/posts/1'])
            expect(rss.to_s).not_to match(/<enclosure|&lt;(?:audio|video)|javascript:|data:audio|ftp:/)
            expect(result.to_json_feed[:items].map { _1[:attachments] }).to eq([nil])
          end
        end
      end
    end

    # The t4 corpus page names its hosting platform as meta author; its podcast feed states the show's.
    context 'when a podcast page advertises its native feed' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:dir) { 'spec/fixtures/auto_source/corpus/t4_podcast_feed_enclosures' }
      let(:responses) do
        {
          'https://example.com/news/' => AutoSourceCorpus.response(path: "#{dir}.html", url: 'https://example.com/news/'),
          'https://example.com/news/podcast.xml' =>
            AutoSourceCorpus.response(path: "#{dir}/podcast.xml", url: 'https://example.com/news/podcast.xml')
        }
      end
      let(:channel_tag_for) do
        lambda do |channel|
          Nokogiri::XML(described_class.new({ channel:, auto_source: {} }).to_result.to_rss.to_s)
                  .at_xpath('/rss/channel')
        end
      end
      let(:channel_tag) { channel_tag_for.call({ url: 'https://example.com/news/' }) }

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :default

          responses.fetch(ctx.url.to_s) { raise Html2rss::RequestService::ConnectionFailed, ctx.url.to_s }
        end
      end

      it 'takes the show author, categories and explicit flag from the feed', :aggregate_failures do
        expect(channel_tag.at_xpath('itunes:author').text).to eq('Example Harbor Hour Team')
        expect(channel_tag.xpath('itunes:category').map { _1['text'] }).to eq(['News', 'Society & Culture'])
        expect(channel_tag.xpath('itunes:category/itunes:category').map { _1['text'] }).to eq(['Daily News'])
        expect(channel_tag.at_xpath('itunes:explicit').text).to eq('false')
        expect(channel_tag.xpath('managingEditor')).to be_empty
      end

      it 'keeps a configured channel author' do
        configured = channel_tag_for.call({ url: 'https://example.com/news/', author: 'Configured Author' })

        expect(configured.at_xpath('itunes:author').text).to eq('Configured Author')
      end
    end
  end

  describe 'URL path date fallback' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:time_zone) { 'Europe/Berlin' }
    let(:html) { '<html><body></body></html>' }
    let(:config) do
      { channel: { url: 'https://example.com/news', time_zone: }, strategy: :default, auto_source: {} }
    end
    let(:articles) do
      response = build_response.call(body: html)
      allow(Html2rss::RequestService).to receive(:execute) { |ctx, **| ctx.budget.consume! && response }
      described_class.new(config).to_outcome.articles
    end

    context 'with an undated card whose link carries a date' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        '<html><body><main><ul>' \
          '<li><a href="/2026/10/20/harbor-ferry-route-returns">Harbor ferry route returns</a></li>' \
          '<li><a href="/about/team">About the newsroom team</a></li></ul></main></body></html>'
      end

      it 'sets published_at to local midnight on the final article', :aggregate_failures do
        dated = articles.find { _1.url.to_s.include?('harbor') }

        expect(dated.published_at.to_s).to eq('2026-10-20T00:00:00+02:00')
      end
    end

    context 'when every card carries the same category' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        cards = [['harbor-ferry-route-returns', 'Harbor ferry route returns'],
                 ['city-park-opens', 'City park opens today'],
                 ['library-hours-change', 'Library hours change soon']]
        items = cards.map do |slug, title|
          "<li><span class=\"category\">News</span><a href=\"/#{slug}\">#{title}</a></li>"
        end
        "<html><body><main><ul>#{items.join}</ul></main></body></html>"
      end

      it 'drops the shared category from every item' do
        expect(articles.flat_map(&:categories)).to be_empty
      end
    end

    context 'when only two cards carry the same category' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        cards = [['harbor-ferry-route-returns', 'Harbor ferry route returns'],
                 ['city-park-opens', 'City park opens today']]
        items = cards.map do |slug, title|
          "<li><span class=\"category\">News</span><a href=\"/#{slug}\">#{title}</a></li>"
        end
        "<html><body><main><ul>#{items.join}</ul></main></body></html>"
      end

      it 'keeps it' do
        expect(articles.flat_map(&:categories)).to eq(%w[News News])
      end
    end

    context 'when a native feed carries the same category on every item' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        items = %w[one two three].map do |slug|
          "<item><title>Story #{slug}</title><link>https://example.com/#{slug}</link>" \
            "<guid>https://example.com/#{slug}</guid><category>News</category></item>"
        end
        '<rss version="2.0"><channel><title>Feed</title><link>https://example.com/</link>' \
          "<description>d</description>#{items.join}</channel></rss>"
      end
      let(:articles) do
        response = build_response.call(body: html, headers: { 'content-type' => 'application/rss+xml' })
        allow(Html2rss::RequestService).to receive(:execute) { |ctx, **| ctx.budget.consume! && response }
        described_class.new(config).to_outcome.articles
      end

      it 'keeps the publisher categories' do
        expect(articles.flat_map(&:categories)).to eq(%w[News News News])
      end
    end

    context 'when a single card carries a category' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        '<html><body><main><ul><li><span class="category">News</span>' \
          '<a href="/harbor-ferry-route-returns">Harbor ferry route returns</a></li></ul></main></body></html>'
      end

      it 'keeps it' do
        expect(articles.flat_map(&:categories)).to eq(['News'])
      end
    end

    context 'with a markup date and a parent summary (card-walk shape)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        '<html><body><main><ul><li><a href="/2024/05/03/some-story">Headline of the story</a>' \
          '<p><time datetime="2024-05-04T09:00:00Z">4 May 2024</time> - a longer summary sentence.</p></li>' \
          '<li><a href="/2024/05/02/other-story">Another headline of a story</a>' \
          '<p><time datetime="2024-05-03T09:00:00Z">3 May 2024</time> - another summary sentence.</p></li>' \
          '</ul></main></body></html>'
      end

      it 'keeps the description and the markup date', :aggregate_failures do
        article = articles.find { _1.url.to_s.include?('some-story') }

        expect(article.description).to include('summary sentence')
        expect(article.published_at.to_s).to eq('2024-05-04T09:00:00+00:00')
      end
    end

    context 'when structured data and a card both describe one article' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:html) do
        <<~HTML
          <html><head><script type="application/ld+json">
          {"@context":"https://schema.org","@type":"NewsArticle","headline":"Harbor ferry route returns",
           "url":"https://example.com/2026/10/20/harbor-ferry-route-returns","datePublished":"2026-10-21T08:30:00Z"}
          </script></head><body><main><ul>
          <li><a href="/2026/10/20/harbor-ferry-route-returns">Harbor ferry route returns</a></li>
          </ul></main></body></html>
        HTML
      end

      it 'keeps the structured-data time over the URL date', :aggregate_failures do
        article = articles.find { _1.url.to_s.include?('harbor') }

        expect(article.published_at.to_s).to eq('2026-10-21T08:30:00+00:00')
      end
    end
  end

  describe 'an advertised feed' do
    let(:page) do
      '<html><head><title>Blog</title><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head>' \
        '<body><a href="/a">A</a></body></html>'
    end
    let(:rss) do
      items = (1..3).map do |i|
        "<item><title>Post #{i}</title><link>https://example.com/p#{i}</link><guid>p#{i}</guid>" \
          "<description>Body #{i} text</description></item>"
      end
      '<?xml version="1.0"?><rss version="2.0"><channel><title>T</title><link>https://example.com/</link>' \
        "<description>d</description>#{items.join}</channel></rss>"
    end

    before do
      stub_request(:get, %r{\Ahttps://example\.com/(?!feed\.xml\z)}).to_return(
        status: 200, body: page, headers: { 'Content-Type' => 'text/html' }
      )
      stub_request(:get, 'https://example.com/feed.xml').to_return(
        status: 200, body: rss, headers: { 'Content-Type' => 'application/rss+xml' }
      )
    end

    it 'is fetched once per build', :aggregate_failures do
      feed = Html2rss.feed(channel: { url: 'https://example.com/' }, auto_source: {})

      expect(feed.items.size).to eq(3)
      expect(a_request(:get, 'https://example.com/feed.xml')).to have_been_made.once
    end
  end

  describe 'empty-feed guidance' do
    let(:attempts) { [{ strategy: :default, items_count: 0, error_class: nil }] }
    let(:botasaurus_hint) { Html2rss::RequestService::BotasaurusConfigurationError::EMPTY_FEED_HINT }

    it 'separates surface guidance with a space' do
      error = described_class.empty_feed_error(attempts:, surface_category: :app_shell)
      guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:app_shell)

      expect(error.message).to end_with("selectors. #{guidance}")
    end

    it 'does not append guidance for unsupported_surface' do
      error = described_class.empty_feed_error(attempts:, surface_category: :unsupported_surface)
      guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:unsupported_surface)

      expect(error.message).not_to include(guidance)
    end

    it 'keeps the base empty-feed message without a surface hint', :aggregate_failures do
      error = described_class.empty_feed_error(attempts:)

      expect(error.message).to include('No feed items extracted after auto fallback')
      expect(error.message).not_to include('app-shell surface detected')
      expect(error.message).not_to include(botasaurus_hint)
      expect(error.message).not_to end_with(' ')
    end

    it 'appends shared Scraper guidance for app_shell', :aggregate_failures do
      error = described_class.empty_feed_error(attempts:, surface_category: :app_shell)
      guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:app_shell)

      expect(error.surface_category).to eq(:app_shell)
      expect(error.message).to include(guidance)
      expect(error.message).not_to include('No scrapers found:')
    end

    it 'appends shared Scraper guidance for high_entropy_surface', :aggregate_failures do
      error = described_class.empty_feed_error(attempts:, surface_category: :high_entropy_surface)
      guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:high_entropy_surface)

      expect(error.surface_category).to eq(:high_entropy_surface)
      expect(error.message).to include(guidance)
      expect(error.message).to include('listing/update URL')
    end

    context 'when a BotasaurusConfigurationError attempt is present' do
      let(:attempts) do
        [
          { strategy: :default, items_count: 0, error_class: nil },
          {
            strategy: :botasaurus,
            items_count: nil,
            error_class: 'Html2rss::RequestService::BotasaurusConfigurationError'
          }
        ]
      end

      it 'appends the owned Botasaurus config hint once', :aggregate_failures do
        error = described_class.empty_feed_error(attempts:)

        expect(error.message).to include(botasaurus_hint)
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end

      # rubocop:disable-next RSpec/ExampleLength -- guidance + hint + no twin BOTASAURUS assert
      it 'appends the Botasaurus config hint beside app_shell guidance', :aggregate_failures do
        error = described_class.empty_feed_error(attempts:, surface_category: :app_shell)
        guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:app_shell)

        expect(error.message).to include(guidance)
        expect(error.message).to include(botasaurus_hint)
        expect(guidance).not_to include('BOTASAURUS_SCRAPER_URL')
        expect(error.message).to end_with("#{guidance} #{botasaurus_hint}")
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end

      it 'does not twin Botasaurus prose when blocked_surface already covers it', :aggregate_failures do
        error = described_class.empty_feed_error(attempts:, surface_category: :blocked_surface)
        guidance = Html2rss::AutoSource::SurfaceCategory::MESSAGES.fetch(:blocked_surface)

        expect(error.message).to include(guidance)
        expect(error.message).not_to include(botasaurus_hint)
        expect(error.message.scan('BOTASAURUS_SCRAPER_URL').size).to eq(1)
      end
    end
  end
end
