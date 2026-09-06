# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'mcp'
require 'rss'

# rubocop:disable-next RSpec/DescribeClass -- integration policy spec; lives under spec/integration/
RSpec.describe 'curation golden path (MCP policy)' do
  subject(:protocol_server) { Html2rss::MCP::Server.build }

  let(:url) { 'https://example.com/news' }
  let(:valid_config) do
    {
      channel: { url:, title: 'Example News', time_zone: 'UTC' },
      selectors: {
        items: { selector: 'div.item', enhance: false },
        title: { selector: 'h2' },
        url: { selector: 'a', extractor: 'href' }
      }
    }
  end

  let(:call_tool) do
    lambda do |name, arguments|
      payload = {
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name:, arguments: }
      }
      JSON.parse(protocol_server.handle_json(JSON.generate(payload)), symbolize_names: true)
    end
  end

  let(:envelope_for) do
    lambda do |name, arguments|
      result = call_tool.call(name, arguments)
      JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)
    end
  end

  describe 'defer verdict stops before capture (native feed wins)' do
    before do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:call).and_return(
        Html2rss::PageRecon::Diagnostics::Report.new(
          data: {
            requested_url: url,
            alternate_feeds: [{ href: 'https://example.com/feed.xml', type: 'application/rss+xml' }]
          }
        )
      )
      allow(Html2rss).to receive(:recon).and_return(
        Html2rss::Recon::Result.new(
          requested_url: url,
          final_url: url,
          status: 200,
          verdict: Html2rss::Recon::Verdict.coerce(:defer),
          native_feed: 'https://example.com/feed.xml',
          surface_category: :article_listing,
          articles_count: 0,
          scheme_downgrade: false,
          notes: ['Native RSS/Atom feed present'],
          html_bytesize: 500
        )
      )
      allow(Html2rss::Capture).to receive(:build)
    end

    # rubocop:disable-next RSpec/ExampleLength -- policy chain is one story
    it 'routes inspect → recon → done without calling capture', :aggregate_failures do
      inspect_env = envelope_for.call('inspect', { url: })
      recon_env = envelope_for.call('recon', { url: })

      expect(inspect_env).to include(ok: true, next_step: 'recon')
      expect(recon_env).to include(
        ok: true,
        next_step: 'done',
        payload: hash_including(
          verdict: 'defer',
          native_feed: 'https://example.com/feed.xml'
        )
      )
      expect(Html2rss::Capture).not_to have_received(:build)
    end
  end

  describe 'build verdict walks inspect → recon → capture → test → apply' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- golden path stubs one chain
    let(:capture_result) do
      Html2rss::Capture::CaptureResult.new(
        config: valid_config,
        articles_count: 3,
        channel_title: 'Example News',
        has_selectors: true,
        segment_strategy: :list,
        admission_drops: {},
        selected_strategy: nil
      )
    end

    let(:rss_items) do
      [
        instance_double(
          RSS::Rss::Channel::Item,
          title: 'Story One Title Here',
          link: 'https://example.com/a',
          pubDate: nil
        ),
        instance_double(
          RSS::Rss::Channel::Item,
          title: 'Story Two Title Here',
          link: 'https://example.com/b',
          pubDate: nil
        )
      ]
    end

    let(:feed_result) do
      status = instance_double(
        Html2rss::Status,
        selected_strategy: :default,
        entry_url: url,
        scrape_url: url
      )
      instance_double(
        Html2rss::FeedResult,
        empty?: false,
        to_rss: instance_double(RSS::Rss, to_s: '<rss version="2.0"/>', items: rss_items),
        status:
      )
    end

    before do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:call).and_return(
        Html2rss::PageRecon::Diagnostics::Report.new(
          data: {
            requested_url: url,
            alternate_feeds: [{ href: 'https://example.com/feed.xml', type: 'application/rss+xml' }]
          }
        )
      )
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
      outcome = Html2rss::FeedPipeline::PipelineOutcome.new(
        response: Html2rss::RequestService::Response.new(
          url:,
          headers: { 'content-type' => 'text/html' },
          body: '<html></html>'
        ),
        articles: [],
        dedup_dropped: 0,
        selected_strategy: :default,
        attempt_count: 0,
        strategy_attempts: [],
        admission_drops: {},
        scrape_target: nil,
        entry_resolution: nil
      )
      pipeline = instance_double(Html2rss::FeedPipeline, to_outcome_and_result: [outcome, feed_result])
      allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
      allow(Html2rss).to receive_messages(
        recon: Html2rss::Recon::Result.new(
          requested_url: url,
          final_url: url,
          status: 200,
          verdict: Html2rss::Recon::Verdict.coerce(:build),
          native_feed: nil,
          surface_category: :article_listing,
          articles_count: 3,
          scheme_downgrade: false,
          notes: [],
          html_bytesize: 12_000
        ),
        test: Html2rss::Test::Result.new(
          success: true,
          item_count: 2,
          sample_items: [{ title: 'A', url: 'https://example.com/a' }],
          channel_title: 'Example News',
          channel_url: url,
          strategy_used: :default,
          duration_seconds: 0.2,
          validation_errors: nil,
          error_message: nil,
          failure_kind: nil,
          rss: '<rss/>'
        )
      )
      allow(Html2rss::Capture).to receive(:build).and_return(capture_result)
    end

    # rubocop:disable-next RSpec/ExampleLength -- golden path encodes policy, not just happy-path wiring
    it 'follows each next_step through the ship gate', :aggregate_failures do
      inspect_env = envelope_for.call('inspect', { url: })
      recon_env = envelope_for.call('recon', { url: })
      capture_env = envelope_for.call('capture', { url: })
      test_env = envelope_for.call('test', { yaml: capture_result.yaml, min_items: 1 })
      apply_env = envelope_for.call('apply', { url:, yaml: capture_result.yaml })

      expect(inspect_env[:next_step]).to eq('recon')
      expect(recon_env).to include(ok: true, next_step: 'capture', payload: hash_including(verdict: 'build'))
      expect(capture_env).to include(ok: true, next_step: 'test')
      expect(capture_env.dig(:payload, :yaml)).to include('channel:')
      expect(test_env).to include(ok: true, next_step: 'apply', payload: hash_including(item_count: 2))
      expect(apply_env).to include(
        ok: true,
        next_step: 'done',
        payload: hash_including(item_count: 2, rss: '<rss version="2.0"/>')
      )
    end
  end
end
