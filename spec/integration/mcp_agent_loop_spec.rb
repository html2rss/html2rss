# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

# rubocop:disable-next RSpec/DescribeClass -- integration policy spec; lives under spec/integration/
RSpec.describe 'MCP agent loop (next_step terminates, guidance names real fields)' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- one world table, built from named parts
  let(:outcome) { Html2rss::MCP::Outcome }
  let(:request_service) { Html2rss::RequestService }
  let(:scrape_url) { 'https://example.com/page' }
  let(:capture_base) do
    { config: {}, yaml: "channel:\n  url: https://example.com\n", articles_count: 3, has_selectors: true,
      channel_title: 'Example', segment_strategy: nil }
  end

  # What each tool returns when the agent follows next_step, for one fixed world of page facts.
  let(:healthy) do
    {
      scrape: outcome.scrape(items: [{ title: 'A' }], requested_strategy: :auto, channel_title: 'C', scrape_url:,
                             botasaurus_configured: true),
      inspect: outcome.inspect_report(report: report(html_response: true, articles_count: 3, strategy: :default),
                                      botasaurus_configured: true),
      recon: outcome.recon(result: recon_result(verdict: :build)),
      capture: outcome.capture(result: Html2rss::Curation::Capture::CaptureResult.new(**capture_base),
                               requested_strategy: :auto),
      validate: outcome.validate(report: Html2rss::Config::ValidationReport.ok),
      test: outcome.test(test_result(success: true)),
      apply: outcome.apply(rss: '<rss/>', item_count: 2)
    }
  end
  let(:empty_capture) do
    outcome.capture(result: Html2rss::Curation::Capture::CaptureResult.new(**capture_base, articles_count: 0),
                    requested_strategy: :auto)
  end
  let(:empty_scrape) do
    lambda do |configured, strategy = :auto|
      outcome.scrape(items: [], requested_strategy: strategy, channel_title: 'C', scrape_url:,
                     botasaurus_configured: configured)
    end
  end
  let(:inspect_of) do
    lambda do |configured, **facts|
      outcome.inspect_report(report: report(html_response: true, strategy: :default, **facts),
                             botasaurus_configured: configured)
    end
  end
  let(:no_feed_items) do
    lambda do |surface, *strategies|
      attempts = strategies.map { |strategy| { strategy:, items_count: 0 } }
      Html2rss::NoFeedItemsExtracted.new(attempts:, surface_category: surface)
    end
  end

  # World name => the table overrides for that page; every other tool keeps its healthy answer.
  let(:worlds) do
    {
      'a PDF, scrape returns nothing' => {
        scrape: empty_scrape.call(false),
        inspect: inspect_of.call(false, html_response: false, content_type: 'application/pdf',
                                        surface_category: 'unsupported_surface'),
        capture: empty_capture
      },
      'an image, scrape fails on an unsupported surface' => {
        scrape: outcome.from_error(no_feed_items.call(:unsupported_surface, :default), url: scrape_url, tool: 'scrape'),
        inspect: inspect_of.call(true, html_response: false, content_type: 'image/png'),
        capture: empty_capture
      },
      'a redirect URL that lands on nothing readable' => {
        scrape: outcome.from_error(no_feed_items.call(:unsupported_surface, :default, :botasaurus),
                                   url: scrape_url, tool: 'scrape'),
        inspect: inspect_of.call(true, articles_count: 0, surface_category: 'unsupported_surface'),
        capture: empty_capture
      },
      'a JS shell with Botasaurus configured' => {
        scrape: empty_scrape.call(true),
        inspect: inspect_of.call(true, articles_count: 0, likely_js_shell: true, surface_category: 'app_shell'),
        capture: empty_capture
      },
      'a JS shell with Botasaurus unset' => {
        scrape: empty_scrape.call(false),
        inspect: inspect_of.call(false, articles_count: 0, likely_js_shell: true, surface_category: 'app_shell'),
        capture: empty_capture
      },
      'a JS shell after an explicit default scrape, then the botasaurus retry' => {
        scrape: empty_scrape.call(true, :botasaurus),
        inspect: inspect_of.call(true, articles_count: 0, likely_js_shell: true),
        capture: empty_capture
      },
      'a static page without articles' => {
        scrape: empty_scrape.call(false),
        inspect: inspect_of.call(true, articles_count: 0, surface_category: 'listing'),
        capture: empty_capture
      },
      'a blocked page that Botasaurus also fails on' => {
        scrape: outcome.from_error(no_feed_items.call(:blocked_surface, :default, :botasaurus),
                                   url: scrape_url, tool: 'scrape'),
        inspect: inspect_of.call(true, articles_count: 0, blocked_surface: true, strategy: :botasaurus),
        capture: empty_capture
      },
      'a recon drop' => {
        recon: outcome.recon(result: recon_result(verdict: :drop, articles_count: 0)),
        scrape: empty_scrape.call(false),
        inspect: inspect_of.call(false, html_response: false),
        capture: empty_capture
      },
      'a config that fails at test' => {
        test: outcome.test(test_result(failure_kind: Html2rss::Curation::Test::FailureKind[:min_items]))
      },
      'a config that renders nothing' => {
        apply: outcome.apply(rss: '<rss/>', item_count: 0)
      }
    }
  end

  # A tool that fails the same way every time it is called.
  let(:timed_out_everywhere) do
    request_service::RequestTimedOut.new('slow').tap do |error|
      error.attempts = [{ strategy: :default, error_class: request_service::RequestTimedOut.name }]
    end
  end
  let(:errors) do
    [
      request_service::RequestTimedOut.new('slow'),
      timed_out_everywhere,
      request_service::UnsupportedUrlScheme.new('downgraded', retry_url: 'https://example.com/a'),
      request_service::ConnectionFailed.new('refused'),
      request_service::BlockedSurfaceDetected.new('blocked'),
      request_service::BotasaurusConfigurationError.new('unset'),
      Html2rss::InvalidOption.new('bad option'),
      Html2rss::MCP::Contract::InvalidArgumentsError.new('Missing required arguments: url'),
      Html2rss::MCP::Contract::UnpublishedRequestError.new('unpublished'),
      no_feed_items.call(:unsupported_surface, :default),
      no_feed_items.call(:app_shell, :default, :botasaurus),
      no_feed_items.call(:app_shell, :default),
      StandardError.new('boom')
    ]
  end
  let(:always_failing) do
    lambda do |error|
      %w[scrape inspect recon capture validate test apply].to_h do |tool|
        [tool.to_sym, outcome.from_error(error, url: scrape_url, tool:)]
      end
    end
  end

  # Starting points no table entry covers: a scrape that only ran the default strategy.
  let(:default_only_scrape) { empty_scrape.call(true, :default) }

  let(:terminal) { %i[done stop read_runtime] }
  # Follows next_step through the table. +validate+ after a failed outcome means "fix the input and call again":
  # the caller changes the arguments, so it ends the walk like a terminal step.
  let(:walk) do
    lambda do |start, table|
      current = start
      5.times do
        step = current.next_step.name
        return step if terminal.include?(step) || (step == :validate && !current.ok)

        current = table.fetch(step)
      end
      :cycle
    end
  end

  let(:timed_out) { request_service::RequestTimedOut.new('slow') }
  let(:batch_failures) do
    batch = Html2rss::Curation::Batch::BatchResult
    failed = { url: scrape_url, ok: false, error: 'x' }
    [
      outcome.batch_scrape(batch.new(total: 1, successful: 0, results: [failed], errors: [timed_out])),
      outcome.batch_inspect(batch.new(total: 1, successful: 0, results: [{ html_response: false }]),
                            botasaurus_configured: true),
      outcome.batch_recon(batch.new(total: 1, successful: 0, results: [{ verdict: :drop }]))
    ]
  end

  # Every [tool, outcome] the fixtures can produce; a tool's emitted keys are the union over its outcomes, so
  # conditional keys (entry_resolution, url, status, quality_report) count.
  let(:tool_outcomes) do
    from_worlds = ([healthy] + worlds.values).flat_map(&:to_a)
    from_errors = errors.flat_map do |error|
      always_failing.call(error).map { |tool, failure| [tool, failure] }
    end
    extras = [[:scrape, resolved_scrape], [:inspect, outcome.from_error(errors.first)],
              [:test, outcome.test(test_result(success: true, quality_report: warned_report))],
              [:validate, outcome.validate(report: Html2rss::Config::ValidationReport.failure([]))]]
    from_worlds + from_errors + extras + %i[scrape inspect recon].zip(batch_failures)
  end
  let(:resolved_scrape) do
    outcome.scrape(items: [{ title: 'A' }], requested_strategy: :auto, channel_title: 'C', scrape_url:,
                   botasaurus_configured: true, admission_drops: { 'credit' => 1 },
                   entry_resolution: { applied: true, reason: :winner })
  end
  let(:warned_report) do
    Html2rss::Curation::Test::QualityReport.new(warnings: [:duplicate_urls], metrics: {}, native_feed: nil,
                                                defer_reason: nil)
  end

  # rubocop:disable-next RSpec/ExampleLength -- one walk over a table
  it 'reaches done or stop within 5 hops from every outcome in every page world', :aggregate_failures do
    worlds.each do |world, overrides|
      table = healthy.merge(overrides)
      [*table.values, default_only_scrape].each do |start|
        expect(walk.call(start, table)).not_to eq(:cycle), "#{world}: #{start.next_step.name} never terminates"
      end
    end
  end

  # rubocop:disable-next RSpec/ExampleLength -- one walk over a table
  it 'reaches done or stop within 5 hops from the first failure of a tool that always fails', :aggregate_failures do
    errors.each do |error|
      table = always_failing.call(error)
      table.each_value do |start|
        expect(walk.call(start, table)).not_to eq(:cycle), "#{error.class}: #{start.next_step.name} never terminates"
      end
    end
  end

  it 'terminates from a batch where nothing succeeded', :aggregate_failures do
    batch_failures.each do |start|
      expect(walk.call(start, healthy)).not_to eq(:cycle)
    end
  end

  # rubocop:disable-next RSpec/ExampleLength -- one walk over a table
  it 'only names payload fields the outcome or the tool its next_step calls can emit', :aggregate_failures do
    emits = tool_outcomes.group_by(&:first).transform_values do |pairs|
      pairs.flat_map { |_, entry| entry.payload.keys }.uniq
    end

    tool_outcomes.each do |tool, entry|
      allowed = emits.fetch(tool) + emits.fetch(entry.next_step.name, [])
      entry.guidance.scan(/payload\.(\w+)/).flatten.each do |key|
        expect(allowed).to include(key.to_sym), "#{tool} -> #{entry.next_step.name} guidance names payload.#{key}"
      end
    end
  end
end
