# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Outcome do
  describe Html2rss::MCP::Outcome::NextStep do
    it 'exposes the closed set of wire names from Playbook guidance' do
      expect(described_class::ALL.keys.map(&:to_s)).to contain_exactly(
        'done', 'inspect', 'recon', 'validate', 'apply',
        'scrape', 'capture', 'read_runtime', 'test', 'stop'
      )
    end

    it 'cannot be built with an unknown name' do
      expect { described_class[:retry_invalid] }
        .to raise_error(Html2rss::InvalidOption, /unknown next_step/)
    end

    it 'owns guidance copy on each named instance' do
      expect(described_class[:inspect].guidance).to include('inspect')
    end
  end

  describe Html2rss::MCP::Outcome::Playbook do
    it 'owns server instructions with bare verb tool names', :aggregate_failures do
      expect(described_class.instructions).to include('→ scrape').and include('→ capture → test → apply')
      expect(described_class.instructions).to include('payload.scrape_url', 'payload.entry_resolution')
    end

    it 'embeds auto strategy guidance in scrape_webpage_prompt' do
      prompt = described_class.scrape_webpage_prompt('https://example.com')

      expect(prompt).to include('https://example.com', 'strategy auto', 'payload.items')
    end

    it 'embeds the enhance default in capture_feed_config_prompt' do
      prompt = described_class.capture_feed_config_prompt('https://example.com')

      expect(prompt).to include('suggested_channel_url', 'enhance defaults to true')
    end

    describe '.guidance' do
      it 'is the step copy alone without a reason' do
        expect(described_class.guidance(Html2rss::MCP::Outcome::NextStep[:capture]))
          .to eq(described_class::GUIDANCE.fetch(:capture))
      end

      it 'appends the reason the step was chosen' do
        expect(described_class.guidance(Html2rss::MCP::Outcome::NextStep[:stop], :not_html))
          .to eq("#{described_class::GUIDANCE.fetch(:stop)} #{described_class::REASONS.fetch(:not_html)}")
      end
    end

    describe '.recon_guidance' do
      it 'appends scheme downgrade hint' do
        result = instance_double(Html2rss::Curation::Recon::Result, scheme_downgrade: true)
        next_step = Html2rss::MCP::Outcome::NextStep[:capture]

        expect(described_class.recon_guidance(result, next_step))
          .to include('HTTPS→HTTP downgrade', next_step.guidance)
      end

      it 'returns next_step guidance when scheme is not downgraded' do
        result = instance_double(Html2rss::Curation::Recon::Result, scheme_downgrade: false)
        next_step = Html2rss::MCP::Outcome::NextStep[:capture]

        expect(described_class.recon_guidance(result, next_step)).to eq(next_step.guidance)
      end
    end
  end

  describe '.scrape' do
    let(:items) { [{ title: 'A', url: 'https://example.com/a' }] }

    it 'succeeds with next_step done when articles are present', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- payload keys are one story
      outcome = described_class.scrape(
        items:, requested_strategy: :auto, channel_title: 'Channel', scrape_url: 'https://example.com/',
        botasaurus_configured: false
      )

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:done)
      expect(outcome.payload).to include(
        items:, total: 1, requested_strategy: 'auto', channel_title: 'Channel'
      )
      expect(outcome.payload).not_to have_key(:admission_drops)
    end

    describe 'effective page' do
      let(:resolution) { { applied: true, probe_count: 5, reason: :winner, winner_score: 750 } }
      let(:base) { { items:, requested_strategy: :auto, channel_title: 'C', botasaurus_configured: true } }

      it 'always carries scrape_url and omits empty extras by default' do
        outcome = described_class.scrape(**base, scrape_url: 'https://example.com/', admission_drops: {})

        expect(outcome.payload).to eq(items:, total: 1, requested_strategy: 'auto', channel_title: 'C',
                                      scrape_url: 'https://example.com/')
      end

      it 'carries entry_resolution when given' do
        payload = described_class.scrape(**base, scrape_url: 'https://example.com/index~atom.xml',
                                                 entry_resolution: resolution).payload

        expect(payload).to include(scrape_url: 'https://example.com/index~atom.xml', entry_resolution: resolution)
      end

      it 'keeps the done guidance' do
        expect(described_class.scrape(**base, scrape_url: 'https://example.com/').guidance)
          .to eq(described_class::Playbook::GUIDANCE.fetch(:done))
      end
    end

    {
      'auto with Botasaurus configured' => [:auto, true, :stop, :browser_exhausted],
      'botasaurus with Botasaurus configured' => [:botasaurus, true, :stop, :browser_exhausted],
      'default with Botasaurus configured' => [:default, true, :inspect, nil],
      'auto with Botasaurus unset' => [:auto, false, :inspect, nil],
      'default with Botasaurus unset' => [:default, false, :inspect, nil]
    }.each do |label, (strategy, configured, step, reason)|
      it "keeps ok true and points at #{step} when empty after #{label}", :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one envelope
        outcome = described_class.scrape(
          items: [], requested_strategy: strategy, channel_title: 'Channel', scrape_url: 'https://example.com/',
          botasaurus_configured: configured
        )

        expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: step))
        expect(outcome.guidance).to eq(
          described_class::Playbook.guidance(described_class::NextStep[step], reason)
        )
      end
    end

    it 'includes admission_drops only when present' do
      outcome = described_class.scrape(
        items:, requested_strategy: :auto, channel_title: 'Channel',
        admission_drops: { 'credit' => 1 }, scrape_url: 'https://example.com/', botasaurus_configured: true
      )

      expect(outcome.payload[:admission_drops]).to eq('credit' => 1)
    end
  end

  describe '.inspect_report' do
    let(:html) { { html_response: true, strategy: :default } }

    {
      'alternates are present' =>
        [{ alternate_feeds: [{ href: 'https://example.com/feed.xml' }] }, true, :recon, nil],
      'extractable articles are present' => [{ articles_count: 3 }, true, :capture, nil],
      'the response is not HTML' => [{ html_response: false, content_type: 'application/pdf' }, true, :stop, :not_html],
      'the surface is unsupported' => [{ surface_category: 'unsupported_surface' }, true, :stop, :unreadable_surface],
      'the surface category is a symbol' => [{ surface_category: :high_entropy_surface }, true, :stop,
                                             :unreadable_surface],
      'the surface category says blocked' => [{ surface_category: :blocked_surface }, true, :scrape, :js_shell],
      'a static page reports false shell facts' =>
        [{ likely_js_shell: false, blocked_surface: false, surface_category: 'listing' }, true, :capture,
         :static_empty],
      'the surface category is missing' => [{}, true, :capture, :static_empty],
      'the page is a JS shell and Botasaurus is configured' => [{ likely_js_shell: true }, true, :scrape, :js_shell],
      'the page is blocked and Botasaurus is unset' =>
        [{ blocked_surface: true }, false, :read_runtime, :browser_missing],
      'Botasaurus already ran on a JS shell' =>
        [{ likely_js_shell: true, strategy: :botasaurus }, true, :stop, :browser_exhausted],
      'the page is static and empty' => [{ surface_category: 'listing' }, true, :capture, :static_empty]
    }.each do |label, (data, configured, step, reason)|
      it "points at #{step} when #{label}", :aggregate_failures do
        outcome = described_class.inspect_report(report: report(**html, **data), botasaurus_configured: configured)

        expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: step))
        expect(outcome.guidance).to eq(described_class::Playbook.guidance(described_class::NextStep[step], reason))
      end
    end

    it 'treats a missing strategy as not Botasaurus' do
      outcome = described_class.inspect_report(report: report(html_response: true, likely_js_shell: true),
                                               botasaurus_configured: true)

      expect(outcome.next_step.name).to eq(:scrape)
    end

    it 'reads a missing html_response fact as not HTML' do
      outcome = described_class.inspect_report(report:, botasaurus_configured: true)

      expect(outcome.next_step.name).to eq(:stop)
    end
  end

  describe '.recon' do
    it 'points at done when verdict is defer (native feed)' do
      outcome = described_class.recon(
        result: recon_result(verdict: :defer, native_feed: 'https://example.com/feed.xml')
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
    end

    it 'points at capture when verdict is build' do
      outcome = described_class.recon(result: recon_result(verdict: :build))

      expect(outcome.next_step.name).to eq(:capture)
    end

    it 'points at scrape when verdict is drop' do
      outcome = described_class.recon(result: recon_result(verdict: :drop, articles_count: 0))

      expect(outcome.next_step.name).to eq(:scrape)
    end
  end

  describe '.capture' do
    let(:base) do
      { config: {}, yaml: "channel:\n  url: https://example.com\n", articles_count: 3, has_selectors: true,
        channel_title: 'Example', segment_strategy: nil }
    end
    let(:capture) do
      lambda do |requested_strategy: 'auto', **fields|
        described_class.capture(result: Html2rss::Curation::Capture::CaptureResult.new(**base, **fields),
                                requested_strategy:)
      end
    end

    it 'points at test when the draft has articles and selectors' do
      outcome = capture.call

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :test))
    end

    it 'points at done when native_feed is detected', :aggregate_failures do
      outcome = capture.call(native_feed: 'https://example.com/feed.xml')

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
      expect(outcome.payload[:native_feed]).to eq('https://example.com/feed.xml')
    end

    it 'stops when articles_count is zero' do
      outcome = capture.call(articles_count: 0)

      expect(outcome).to have_attributes(next_step: have_attributes(name: :stop),
                                         guidance: include(described_class::Playbook::REASONS.fetch(:capture_unusable)))
    end

    it 'points at scrape when articles exist but selectors are missing', :aggregate_failures do
      outcome = capture.call(has_selectors: false)

      expect(outcome.next_step.name).to eq(:scrape)
      expect(outcome.guidance).to include(described_class::Playbook::REASONS.fetch(:capture_scrape_only))
    end

    it 'puts YAML inside payload rather than as the whole result' do
      outcome = capture.call

      expect(outcome.payload[:yaml]).to include('channel:')
    end

    it 'emits only the base payload keys when no optional draft fields are given', :aggregate_failures do
      outcome = capture.call

      expect(outcome.payload).to eq(
        yaml: base[:yaml], articles_count: 3, has_selectors: true,
        channel_title: 'Example', requested_strategy: 'auto'
      )
    end

    it 'emits every optional draft field with its wire form when given', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- full wire payload
      outcome = capture.call(
        requested_strategy: :auto, segment_strategy: :rss, selected_strategy: 'html',
        admission_drops: { 'credit' => 1 }, native_feed: URI('https://example.com/feed.xml'),
        suggested_channel_url: URI('https://example.com/')
      )

      expect(outcome.payload).to eq(
        yaml: base[:yaml], articles_count: 3, has_selectors: true, channel_title: 'Example',
        requested_strategy: 'auto', segment_strategy: 'rss', selected_strategy: 'html',
        admission_drops: { 'credit' => 1 }, native_feed: 'https://example.com/feed.xml',
        suggested_channel_url: 'https://example.com/'
      )
    end

    it 'keeps the draft ok and points at test when native_feed is absent', :aggregate_failures do
      outcome = capture.call(articles_count: 1, has_selectors: true)

      expect(outcome).to have_attributes(ok: true, guidance: described_class::NextStep[:test].guidance)
    end
  end

  describe 'batch verbs' do
    let(:batch_result) { Html2rss::Curation::Batch::BatchResult }
    let(:timed_out) { Html2rss::RequestService::RequestTimedOut.new('slow') }
    let(:ok_row) { { url: 'https://example.com/a', ok: true, items_count: 1 } }
    let(:failed_row) { { url: 'https://example.com/b', ok: false, error: 'slow' } }

    describe '.batch_scrape' do
      it 'is done with the plain guidance when every URL succeeded', :aggregate_failures do
        outcome = described_class.batch_scrape(batch_result.new(total: 1, successful: 1, results: [ok_row]))

        expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done),
                                           guidance: described_class::NextStep[:done].guidance)
        expect(outcome.payload).to eq(total: 1, successful: 1, results: [ok_row])
      end

      it 'stays done but counts the failures and sends the agent to each row when some failed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one envelope
        outcome = described_class.batch_scrape(
          batch_result.new(total: 2, successful: 1, results: [ok_row, failed_row], errors: [nil, timed_out])
        )

        expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
        expect(outcome.guidance).to eq(
          "#{described_class::NextStep[:done].guidance} 1 of 2 URLs failed: read each failed row's next_step."
        )
      end

      it 'gives a failed row the single-URL error fields and next_step', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one row
        outcome = described_class.batch_scrape(
          batch_result.new(total: 2, successful: 1, results: [ok_row, failed_row], errors: [nil, timed_out])
        )
        single = described_class.from_error(timed_out, url: failed_row[:url])

        expect(outcome.payload[:results].first).to eq(ok_row)
        expect(outcome.payload[:results].last).to eq(
          failed_row.merge(single.payload, next_step: single.next_step.name.to_s)
        )
        expect(outcome.payload[:results].last).to include(class: 'Html2rss::RequestService::RequestTimedOut',
                                                          next_step: 'inspect', url: failed_row[:url], error: 'slow')
        expect(outcome.payload[:results].last).not_to have_key(:guidance)
      end

      it 'keeps the scrape step when no URL succeeded', :aggregate_failures do
        outcome = described_class.batch_scrape(
          batch_result.new(total: 1, successful: 0, results: [failed_row], errors: [timed_out])
        )

        expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :scrape),
                                           guidance: described_class::NextStep[:scrape].guidance)
      end
    end

    describe '.batch_inspect' do
      let(:rows) do
        [{ requested_url: 'https://example.com/a', status: 200, articles_count: 2, html_response: true },
         { requested_url: 'https://example.com/b', status: 200, articles_count: 0, html_response: false }]
      end

      it 'gives each row the next_step a single inspect would give', :aggregate_failures do
        outcome = described_class.batch_inspect(batch_result.new(total: 2, successful: 1, results: rows),
                                                botasaurus_configured: true)

        expect(outcome.payload[:results].map { |row| row[:next_step] }).to eq(%w[capture stop])
        expect(outcome.guidance).to include('1 of 2 URLs failed')
      end

      it 'asks for the runtime when a JS shell row has no Botasaurus to retry with' do
        row = { requested_url: 'https://example.com/a', status: 200, articles_count: 0, html_response: true,
                likely_js_shell: true }
        outcome = described_class.batch_inspect(batch_result.new(total: 1, successful: 1, results: [row]),
                                                botasaurus_configured: false)

        expect(outcome.payload[:results].first[:next_step]).to eq('read_runtime')
      end

      it 'gives a failed row the error fields and the step a raising single inspect gives', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one row
        outcome = described_class.batch_inspect(
          batch_result.new(total: 2, successful: 1, results: rows, errors: [nil, timed_out]),
          botasaurus_configured: true
        )

        expect(outcome.payload[:results].first[:next_step]).to eq('capture')
        expect(outcome.payload[:results].last).to include(class: 'Html2rss::RequestService::RequestTimedOut',
                                                          message: 'slow', next_step: 'stop')
      end

      it 'keeps the inspect step when no URL succeeded' do
        outcome = described_class.batch_inspect(batch_result.new(total: 2, successful: 0, results: rows),
                                                botasaurus_configured: true)

        expect(outcome.next_step.name).to eq(:inspect)
      end
    end

    describe '.batch_recon' do
      let(:rows) do
        [{ requested_url: 'https://example.com/a', verdict: :build },
         { requested_url: 'https://example.com/b', verdict: :drop }]
      end

      it 'gives each row the next_step a single recon would give', :aggregate_failures do
        outcome = described_class.batch_recon(batch_result.new(total: 2, successful: 1, results: rows))

        expect(outcome.payload[:results].map { |row| row[:next_step] }).to eq(%w[capture scrape])
        expect(outcome.next_step.name).to eq(:done)
      end

      it 'gives a failed row the error fields and the step a raising single recon gives', :aggregate_failures do
        outcome = described_class.batch_recon(
          batch_result.new(total: 2, successful: 1, results: rows, errors: [nil, timed_out])
        )

        expect(outcome.payload[:results].map { |row| row[:next_step] }).to eq(%w[capture inspect])
        expect(outcome.payload[:results].last).to include(class: 'Html2rss::RequestService::RequestTimedOut')
      end

      it 'keeps the recon step when no URL succeeded' do
        outcome = described_class.batch_recon(batch_result.new(total: 2, successful: 0, results: rows))

        expect(outcome.next_step.name).to eq(:recon)
      end
    end
  end

  describe 'test guidance' do
    let(:warned) do
      Html2rss::Curation::Test::QualityReport.new(warnings: %w[thin_titles dup_urls], metrics: {}, native_feed: nil,
                                                  defer_reason: nil)
    end

    it 'uses the apply guidance on success without warnings' do
      outcome = described_class.test(test_result(success: true))

      expect(outcome.guidance).to eq(described_class::NextStep[:apply].guidance)
    end

    it 'appends quality warnings to the apply guidance on success', :aggregate_failures do
      outcome = described_class.test(test_result(success: true, quality_report: warned))

      expect(outcome.guidance).to eq(
        "#{described_class::NextStep[:apply].guidance} Review payload.quality_report warnings: thin_titles, dup_urls."
      )
      expect(outcome.payload[:quality_report]).to include(warnings: %w[thin_titles dup_urls])
    end

    it 'points a min_items failure at the url selector when items lack a URL' do # rubocop:disable RSpec/ExampleLength
      report = Html2rss::Curation::Test::QualityReport.new(
        warnings: [:items_without_url], metrics: { items_without_url: 2 }, native_feed: nil, defer_reason: nil
      )
      outcome = described_class.test(test_result(error_message: 'Extracted 0 items (minimum required: 1)',
                                                 quality_report: report))

      expect(outcome.guidance).to eq(
        'Extracted 0 items (minimum required: 1) ' \
        "#{described_class::Playbook.guidance(described_class::NextStep[:stop], :test_failed)} " \
        'Review payload.quality_report warnings: items_without_url. ' \
        'Items were dropped for having no URL: fix the selectors.url selector (it must match a link on each item).'
      )
    end

    it 'leads with the test error message on failure' do
      outcome = described_class.test(test_result(error_message: 'Feed is empty'))

      expect(outcome.guidance).to start_with('Feed is empty ')
    end

    it 'falls back to the next_step guidance when the failure carries no message' do
      outcome = described_class.test(test_result.with(error_message: nil))

      expect(outcome.guidance).to eq(
        described_class::Playbook.guidance(described_class::NextStep[:stop], :test_failed)
      )
    end
  end

  describe '.validate' do
    it 'points at test with an empty payload on schema success', :aggregate_failures do
      outcome = described_class.validate(report: Html2rss::Config::ValidationReport.ok)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:test)
      expect(outcome.payload).to eq({})
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'stays on validate when schema issues are present', :aggregate_failures do
      issue = Html2rss::Config::ValidationIssue.new(
        path: %i[channel], code: :missing_key, message: 'is missing'
      )
      report = Html2rss::Config::ValidationReport.failure([issue])
      outcome = described_class.validate(report:)

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:validate)
      expect(outcome.payload).to eq(issues: [issue.to_h])
    end
  end

  describe '.test' do
    it 'points at apply on success' do
      expect(described_class.test(test_result(success: true)).next_step.name).to eq(:apply)
    end

    it 'points at validate on schema failure' do # rubocop:disable RSpec/ExampleLength
      result = test_result(
        failure_kind: Html2rss::Curation::Test::FailureKind[:schema],
        validation_issues: [
          Html2rss::Config::ValidationIssue.new(path: %i[channel], code: :missing_key, message: 'missing')
        ],
        error_message: 'Configuration schema validation failed'
      )
      expect(described_class.test(result).next_step.name).to eq(:validate)
    end

    it 'stops on execution failure' do
      result = test_result(failure_kind: Html2rss::Curation::Test::FailureKind[:execution])
      expect(described_class.test(result).next_step.name).to eq(:stop)
    end

    it 'stops on min_items failure' do
      result = test_result(failure_kind: Html2rss::Curation::Test::FailureKind[:min_items])
      expect(described_class.test(result).next_step.name).to eq(:stop)
    end

    it 'stops on quality failure' do
      result = test_result(failure_kind: Html2rss::Curation::Test::FailureKind[:quality])
      expect(described_class.test(result).next_step.name).to eq(:stop)
    end
  end

  describe '.apply' do
    it 'points at done when RSS items exist', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 1)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:done)
      expect(outcome.guidance).to eq(described_class::NextStep[:done].guidance)
      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 1)
    end

    it 'is not ok and stops when item_count is zero' do
      outcome = described_class.apply(rss: '<rss/>', item_count: 0)

      expect(outcome).to have_attributes(
        ok: false, next_step: have_attributes(name: :stop),
        guidance: described_class::Playbook.guidance(described_class::NextStep[:stop], :apply_empty)
      )
    end

    it 'is not ok when the ship gate reports empty even with items', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 3, empty: true)

      expect(outcome).to have_attributes(ok: false, next_step: have_attributes(name: :stop))
      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 3)
    end

    it 'includes quality_report in the payload only when given', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 1, quality_report: { warnings: [] })

      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 1, quality_report: { warnings: [] })
    end
  end

  describe '#initialize' do
    let(:done) { described_class::NextStep[:done] }

    it 'rejects a next_step that is not a NextStep' do
      expect { described_class.new(ok: true, next_step: :done, guidance: 'g', payload: {}) }
        .to raise_error(described_class::InvalidError, 'next_step must be a NextStep')
    end

    it 'rejects a payload that is not a Hash' do
      expect { described_class.new(ok: true, next_step: done, guidance: 'g', payload: []) }
        .to raise_error(described_class::InvalidError, 'payload must be a Hash')
    end

    it 'coerces ok to a boolean and freezes a copy of the payload', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- envelope invariants
      source = { a: 1 }
      outcome = described_class.new(ok: 'yes', next_step: done, guidance: :hint, payload: source)

      expect(outcome).to have_attributes(ok: true, guidance: 'hint')
      expect(outcome.guidance).to be_frozen
      expect(outcome.payload).to be_frozen
      expect(source).not_to be_frozen
    end
  end

  describe '.from_error' do
    it 'maps BotasaurusConfigurationError to read_runtime without leaking env', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- class/message only
      error = Html2rss::RequestService::BotasaurusConfigurationError.new('BOTASAURUS_SCRAPER_URL is required')
      outcome = described_class.from_error(error)

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:read_runtime)
      expect(outcome.payload).to eq(
        class: 'Html2rss::RequestService::BotasaurusConfigurationError',
        message: 'BOTASAURUS_SCRAPER_URL is required'
      )
      expect(outcome.payload.keys).to contain_exactly(:class, :message)
    end

    {
      'an unknown surface after the default strategy' => [nil, [:default], :inspect],
      'an app shell after the default strategy' => [:app_shell, [:default], :inspect],
      'a blocked surface Botasaurus never tried' => [:blocked_surface, [:default], :inspect],
      'an app shell Botasaurus also tried' => [:app_shell, %i[default botasaurus], :stop],
      'an unsupported surface' => [:unsupported_surface, [:default], :stop],
      'a high-entropy surface' => [:high_entropy_surface, [:default], :stop]
    }.each do |label, (surface, strategies, step)|
      it "maps NoFeedItemsExtracted on #{label} to #{step}" do
        error = Html2rss::NoFeedItemsExtracted.new(attempts: strategies.map do |strategy|
          { strategy:, items_count: 0 }
        end,
                                                   surface_category: surface)

        expect(described_class.from_error(error).next_step.name).to eq(step)
      end
    end

    it 'never sends the agent back to the tool that just failed', :aggregate_failures do
      error = Html2rss::RequestService::RequestTimedOut.new('slow')

      expect(described_class.from_error(error, tool: 'scrape').next_step.name).to eq(:inspect)
      expect(described_class.from_error(error, tool: 'inspect').next_step.name).to eq(:stop)
    end

    it 'lets a failed validate call point at validate again' do
      error = Html2rss::MCP::Contract::InvalidArgumentsError.new('Missing required arguments: yaml')

      expect(described_class.from_error(error, tool: 'validate')).to have_attributes(
        next_step: have_attributes(name: :validate), guidance: described_class::NextStep[:validate].guidance
      )
    end

    it 'points a failed Botasaurus configuration at the runtime guidance' do
      error = Html2rss::RequestService::BotasaurusConfigurationError.new('unset')

      expect(described_class.from_error(error).guidance).to eq(described_class::NextStep[:read_runtime].guidance)
    end

    it 'maps ExclusiveInputError to validate' do
      error = Html2rss::MCP::ConfigArgument::ExclusiveInputError.new('Provide exactly one of config or yaml')
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:validate)
    end

    it 'maps UnpublishedRequestError to validate' do
      error = Html2rss::MCP::Contract::UnpublishedRequestError.new('MCP does not accept strategy local_file')
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:validate)
    end

    it 'maps another InvalidOption to stop' do
      outcome = described_class.from_error(Html2rss::InvalidOption.new('Provide exactly one of config or yaml'))

      expect(outcome.next_step.name).to eq(:stop)
    end

    it 'maps InvalidOption from the MCP edge to stop', :aggregate_failures do
      outcome = described_class.from_error(Html2rss::InvalidOption.new('config must be a Hash, got String'))

      expect(outcome.next_step.name).to eq(:stop)
      expect(outcome.payload).to eq(class: 'Html2rss::InvalidOption', message: 'config must be a Hash, got String')
    end

    it 'maps other exceptions to stop' do
      outcome = described_class.from_error(StandardError.new('boom'))

      expect(outcome.next_step.name).to eq(:stop)
    end

    it 'maps an internal bug class to stop' do
      expect(described_class.from_error(Encoding::CompatibilityError.new('x')).next_step.name).to eq(:stop)
    end

    it 'maps each deterministic rejection to stop', :aggregate_failures do
      Html2rss::FeedPipeline::AutoFallback::NON_FALLBACK_ERRORS.each do |klass|
        expect(described_class.from_error(klass.new('no')).next_step.name).to eq(:stop)
      end
    end

    it 'maps a deterministic HTTP status to stop and shows the status', :aggregate_failures do
      error = Html2rss::RequestService::DeterministicHttpStatus.new('HTTP 404', status: 404)
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:stop)
      expect(outcome.payload).to include(status: 404)
    end

    it 'maps a subclass of a deterministic rejection to stop' do
      subclass = Class.new(Html2rss::RequestService::InvalidUrl)

      expect(described_class.from_error(subclass.new('no')).next_step.name).to eq(:stop)
    end

    it 'keeps transient transport errors on inspect', :aggregate_failures do
      Html2rss::FeedPipeline::AutoFallback::TERMINAL_TRANSPORT_ERRORS.each do |klass|
        expect(described_class.from_error(klass.new('later')).next_step.name).to eq(:inspect)
      end
    end

    it 'adds the input url to the payload when given', :aggregate_failures do
      outcome = described_class.from_error(StandardError.new('boom'), url: 'https://example.com/a')

      expect(outcome.payload).to eq(class: 'StandardError', message: 'boom', url: 'https://example.com/a')
      expect(described_class.from_error(StandardError.new('boom')).payload).not_to have_key(:url)
    end

    it 'merges the diagnostics an Html2rss::Error carries', :aggregate_failures do
      error = Html2rss::RequestService::RequestTimedOut.new('slow')
      error.transport_meta = { 'request_id' => 'r1' }
      outcome = described_class.from_error(error, url: 'https://example.com')

      expect(outcome.payload).to include(request_id: 'r1', url: 'https://example.com')
    end

    it 'does not promise final_url or status in inspect error guidance', :aggregate_failures do
      outcome = described_class.from_error(Html2rss::RequestService::RequestTimedOut.new('slow'))

      expect(outcome.guidance).to eq(Html2rss::MCP::Outcome::Playbook::ERROR_INSPECT_GUIDANCE)
      expect(outcome.guidance).not_to match(/final_url|status/)
    end

    context 'when every attempted strategy timed out' do
      let(:timeout) { Html2rss::RequestService::RequestTimedOut }
      let(:error) { timeout.new('slow').tap { _1.attempts = [{ error_class: timeout.name }] * 2 } }

      it 'says a retry is unlikely to help' do
        expect(described_class.from_error(error).guidance).to eq(described_class::Playbook::ERROR_TIMEOUT_GUIDANCE)
      end
    end

    context 'when another strategy failed differently before the timeout' do
      let(:timeout) { Html2rss::RequestService::RequestTimedOut }
      let(:error) do
        classes = ['Html2rss::RequestService::ConnectionFailed', timeout.name]
        timeout.new('slow').tap { |error| error.attempts = classes.map { |name| { error_class: name } } }
      end

      it 'keeps the retry guidance' do
        expect(described_class.from_error(error).guidance).to eq(described_class::Playbook::ERROR_INSPECT_GUIDANCE)
      end
    end

    context 'with a redirect downgraded from https to http' do
      let(:error) do
        Html2rss::RequestService::UnsupportedUrlScheme.new('downgraded', retry_url: 'https://example.com/a')
      end

      it 'carries the https target and points guidance at it', :aggregate_failures do
        outcome = described_class.from_error(error, url: 'https://example.com/')

        expect(outcome.payload).to include(retry_url: 'https://example.com/a')
        expect(outcome.guidance).to include('payload.retry_url')
      end

      it 'omits the retry hint without a target' do
        outcome = described_class.from_error(Html2rss::RequestService::UnsupportedUrlScheme.new('x'))

        expect(outcome.guidance).not_to include('retry_url')
      end
    end

    it 'tells the agent not to inspect on stop', :aggregate_failures do
      outcome = described_class.from_error(StandardError.new('boom'))

      expect(outcome.guidance).to eq("#{described_class::NextStep[:stop].guidance} #{described_class::Playbook::ERROR_STOP_GUIDANCE}")
      expect(outcome.guidance).to include('Do not call inspect')
    end
  end

  describe '#to_h' do
    it 'serializes next_step as a wire string and keeps payload', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- wire shape
      outcome = described_class.apply(rss: '<rss/>', item_count: 2)
      wire = outcome.to_h

      expect(wire).to eq(
        ok: true,
        next_step: 'done',
        guidance: outcome.guidance,
        payload: { rss: '<rss/>', item_count: 2 }
      )
      expect(wire[:next_step]).to be_a(String)
    end
  end
end
