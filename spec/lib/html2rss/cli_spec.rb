# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'tempfile'

RSpec.describe Html2rss::CLI do
  subject(:cli) { described_class.new }

  describe '#apply' do
    let(:rss_xml) { '<rss><channel><title>Example</title></channel></rss>' }
    let(:feed_res) do
      instance_double(
        Html2rss::FeedResult,
        to_rss: rss_xml,
        to_json_feed: { title: 'Example', items: [] },
        status: instance_double(Html2rss::Status, to_h: {})
      )
    end

    before do
      allow(Html2rss).to receive(:apply).and_return(feed_res)
    end

    it 'parses the YAML file and prints the RSS feed to stdout' do
      allow(Html2rss::Config).to receive(:from_yaml).and_return({ url: 'https://example.com' })

      expect { cli.apply('example.yml') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'supports --format jsonfeed and --explain' do
      allow(Html2rss::Config).to receive(:from_yaml).and_return({ url: 'https://example.com' })
      expect { cli.invoke(:apply, ['example.yml'], { format: 'jsonfeed', explain: true }) }
        .to output(/"title": "Example"/).to_stdout
    end

    it 'handles local file input via --input' do
      allow(Html2rss::Config).to receive(:from_yaml).and_return({ url: 'https://example.com' })
      expect { cli.invoke(:apply, ['example.yml'], { input: 'spec/fixtures/page_1.html' }) }
        .to output("#{rss_xml}\n").to_stdout
    end

    it 'raises Thor::Error on RedirectLimitReached' do
      allow(Html2rss::Config).to receive(:from_yaml).and_return({ url: 'https://example.com' })
      allow(Html2rss).to receive(:apply).and_raise(Html2rss::RequestService::RedirectLimitReached, 'too many')
      expect { cli.apply('example.yml') }.to raise_error(Thor::Error, /too many/)
    end

    it 'raises Thor::Error on NoFeedItemsExtracted' do
      allow(Html2rss::Config).to receive(:from_yaml).and_return({ url: 'https://example.com' })
      allow(Html2rss).to receive(:apply).and_raise(Html2rss::NoFeedItemsExtracted.new(attempts: []))
      expect { cli.apply('example.yml') }.to raise_error(Thor::Error, /No feed items extracted/)
    end
  end

  describe '#inspect' do
    let(:inspect_data) do
      {
        requested_url: 'https://example.com/news',
        final_url: 'https://example.com/news',
        status: 200,
        surface_category: 'article_list',
        articles_count: 5,
        alternate_feeds: [],
        strategy: :faraday
      }
    end
    let(:report) { instance_double(Html2rss::PageRecon::Diagnostics::Report, to_wire_h: inspect_data) }
    let(:batch_result) do
      Html2rss::Batch::BatchResult.new(total: 1, successful: 1, results: [inspect_data])
    end

    before do
      allow(Html2rss).to receive_messages(inspect: report, batch_inspect: batch_result)
    end

    it 'prints diagnostics card to stdout' do
      expect { cli.inspect('https://example.com/news') }.to output(/Surface:  article_list \(5 articles\)/).to_stdout
    end

    it 'supports --format json' do
      expect { cli.invoke(:inspect, ['https://example.com/news'], { format: 'json' }) }
        .to output(/"articles_count": 5/).to_stdout
    end

    it 'supports batch mode with --file' do # rubocop:disable RSpec/ExampleLength
      Tempfile.create('urls') do |f|
        f.puts('https://example.com/news')
        f.flush
        expect { cli.invoke(:inspect, nil, { file: f.path }) }
          .to output(/Surface:  article_list/).to_stdout
      end
    end

    it 'raises Thor::Error when target is omitted' do
      expect { cli.inspect(nil) }.to raise_error(Thor::Error, /target URL/)
    end

    it 'reads URLs from stdin (-)' do
      allow($stdin).to receive(:readlines).and_return(["https://example.com/news\n"])
      expect { cli.inspect('-') }.to output(/Surface:  article_list/).to_stdout
    end
  end

  describe '#recon' do
    let(:recon_result) do
      Html2rss::Recon::Result.new(
        requested_url: Html2rss::Url.from_absolute('https://example.com/news'),
        final_url: Html2rss::Url.from_absolute('https://example.com/news'),
        status: 200,
        verdict: Html2rss::Recon::Verdict.coerce(:build),
        native_feed: nil,
        surface_category: Html2rss::SurfaceCategory.coerce(:article_list),
        articles_count: 5,
        scheme_downgrade: false,
        notes: [],
        html_bytesize: 2048
      )
    end

    before do
      allow(Html2rss::Recon).to receive(:batch).and_return([recon_result])
    end

    it 'runs reconnaissance and prints card to stdout' do
      expect { cli.recon('https://example.com/news') }.to output(/\[BUILD\]/).to_stdout
    end

    it 'exits with 3 for single URL with DEFER verdict', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      defer_res = Html2rss::Recon::Result.new(
        requested_url: Html2rss::Url.from_absolute('https://example.com/news'),
        final_url: Html2rss::Url.from_absolute('https://example.com/news'),
        status: 200,
        verdict: Html2rss::Recon::Verdict.coerce(:defer),
        native_feed: 'https://example.com/feed.xml',
        surface_category: Html2rss::SurfaceCategory.coerce(:article_list),
        articles_count: 5,
        scheme_downgrade: false,
        notes: [],
        html_bytesize: 2048
      )
      allow(Html2rss::Recon).to receive(:batch).and_return([defer_res])
      expect { cli.recon('https://example.com/news') }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(3)
      end
    end

    it 'exits with 1 for single URL with DROP verdict', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      drop_res = Html2rss::Recon::Result.new(
        requested_url: Html2rss::Url.from_absolute('https://example.com/news'),
        final_url: Html2rss::Url.from_absolute('https://example.com/news'),
        status: 404,
        verdict: Html2rss::Recon::Verdict.coerce(:drop),
        native_feed: nil,
        surface_category: Html2rss::SurfaceCategory.coerce(:unsupported_surface),
        articles_count: 0,
        scheme_downgrade: false,
        notes: [],
        html_bytesize: 0
      )
      allow(Html2rss::Recon).to receive(:batch).and_return([drop_res])
      expect { cli.recon('https://example.com/news') }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(1)
      end
    end

    it 'supports --format json' do
      expect { cli.invoke(:recon, ['https://example.com/news'], { format: 'json' }) }
        .to output(/"verdict": "build"/).to_stdout
    end

    it 'supports --format tsv' do
      expect { cli.invoke(:recon, ['https://example.com/news'], { format: 'tsv' }) }
        .to output(/BUILD\t/).to_stdout
    end

    it 'supports batch mode with --verdict filter and --url-only' do # rubocop:disable RSpec/ExampleLength
      Tempfile.create('urls') do |f|
        f.puts('https://example.com/news')
        f.flush
        expect { cli.invoke(:recon, nil, { file: f.path, verdict: 'BUILD', url_only: true }) }
          .to output(%r{https://example.com/news}).to_stdout
      end
    end

    it 'parses slug\\turl lines from --file into bare URLs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Tempfile.create('urls') do |f|
        f.puts("news\thttps://example.com/news")
        f.puts('# comment')
        f.puts('https://example.com/blog')
        f.flush
        expect { cli.invoke(:recon, nil, { file: f.path, url_only: true }) }
          .to output(%r{https://example.com/news}).to_stdout
        expect(Html2rss::Recon).to have_received(:batch).with(
          ['https://example.com/news', 'https://example.com/blog'],
          hash_including(strategy: :auto)
        )
      end
    end

    it 'raises Thor::Error for an unknown --verdict filter' do # rubocop:disable RSpec/ExampleLength
      Tempfile.create('urls') do |f|
        f.puts('https://example.com/news')
        f.flush
        expect { cli.invoke(:recon, nil, { file: f.path, verdict: 'MAYBE' }) }
          .to raise_error(Thor::Error, /unknown verdict/)
      end
    end

    it 'raises Thor::Error when single URL does not match --verdict filter' do
      expect { cli.invoke(:recon, ['https://example.com/news'], { verdict: 'DEFER' }) }
        .to raise_error(Thor::Error, 'No results matched verdict DEFER')
    end

    it 'raises Thor::Error when target is omitted' do
      expect { cli.recon(nil) }.to raise_error(Thor::Error, /target URL/)
    end

    it 'reads URLs from stdin (-)' do
      allow($stdin).to receive(:readlines).and_return(["https://example.com/news\n"])
      expect { cli.recon('-') }.to output(/\[BUILD\]/).to_stdout
    end
  end

  describe '#capture' do
    let(:captured_config) do
      {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.item', enhance: true } }
      }
    end
    let(:capture_result) do
      Html2rss::Capture::CaptureResult.new(
        config: captured_config,
        yaml: "channel:\n  url: https://example.com\n",
        articles_count: 5,
        channel_title: 'Example',
        has_selectors: true,
        segment_strategy: :list,
        selected_strategy: :faraday,
        inferred_topics: ['tech'],
        native_feed: nil,
        admission_drops: {}
      )
    end

    before do
      allow(Html2rss::Capture).to receive(:build).and_return(capture_result)
    end

    it 'prints captured YAML to stdout' do
      expect { cli.capture('https://example.com') }.to output("channel:\n  url: https://example.com\n").to_stdout
    end

    it 'raises Thor::Error when target and --input are omitted' do
      expect { cli.capture(nil) }.to raise_error(Thor::Error, /URL is required/)
    end

    it 'captures from local file via --input' do
      expect { cli.invoke(:capture, [nil], { input: 'spec/fixtures/page_1.html' }) }
        .to output(/channel:/).to_stdout
    end

    it 'writes captured YAML to file with --write', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Dir.mktmpdir do |dir|
        target_file = File.join(dir, 'feed.yml')
        expect { cli.invoke(:capture, ['https://example.com'], { write: target_file }) }
          .to output(/Wrote captured config to/).to_stdout
        expect(File.read(target_file)).to include('url: https://example.com')
      end
    end

    it 'writes captured YAML to directory with --output-dir', :aggregate_failures do
      Dir.mktmpdir do |dir|
        expect { cli.invoke(:capture, ['https://example.com'], { output_dir: dir }) }
          .to output(/Wrote captured config to/).to_stdout
        expect(File.read(File.join(dir, 'example.com', 'index.yml'))).to include('url: https://example.com')
      end
    end

    it 'warns and exits with code 3 when native feed is found without --force', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      feed_capture_result = Html2rss::Capture::CaptureResult.new(
        config: captured_config,
        yaml: "channel:\n  url: https://example.com\n",
        articles_count: 5,
        channel_title: 'Example',
        has_selectors: true,
        segment_strategy: :list,
        selected_strategy: :faraday,
        inferred_topics: ['tech'],
        native_feed: 'https://example.com/feed.xml',
        admission_drops: {}
      )
      allow(Html2rss::Capture).to receive(:build).and_return(feed_capture_result)

      expect { cli.capture('https://example.com') }
        .to output(%r{First-party RSS/Atom feed detected}).to_stderr
        .and raise_error(SystemExit) do |exit_err|
          expect(exit_err.status).to eq(3)
        end
    end

    it 'supports --explain' do
      expect { cli.invoke(:capture, ['https://example.com'], { explain: true }) }
        .to output(/articles_count/).to_stderr
    end

    it 'forwards --max-redirects and --max-requests to Capture.build' do # rubocop:disable RSpec/ExampleLength -- option wiring contract
      cli.invoke(
        :capture,
        ['https://example.com'],
        { max_redirects: 8, max_requests: 4 }
      )

      expect(Html2rss::Capture).to have_received(:build).with(
        'https://example.com',
        hash_including(max_redirects: 8, max_requests: 4)
      )
    end
  end

  describe '#test' do
    let(:test_result_success) do
      Html2rss::Test::Result.new(
        success: true,
        item_count: 10,
        sample_items: [{ title: 'Item 1', url: 'https://example.com/1', published_at: nil }],
        channel_title: 'Example',
        channel_url: 'https://example.com',
        strategy_used: :faraday,
        duration_seconds: 0.12,
        validation_errors: nil,
        error_message: nil,
        failure_kind: nil,
        rss: '<rss/>'
      )
    end

    let(:test_result_failure) do
      Html2rss::Test::Result.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: 'Example',
        channel_url: 'https://example.com',
        strategy_used: :faraday,
        duration_seconds: 0.12,
        validation_errors: nil,
        error_message: 'Extracted 0 items (minimum required: 1)',
        failure_kind: Html2rss::Test::FailureKind.coerce(:min_items),
        rss: nil
      )
    end

    context 'when test passes' do
      before do
        allow(Html2rss).to receive(:test).and_return(test_result_success)
        allow($stdout).to receive(:tty?).and_return(true)
      end

      it 'prints checkmark summary to stdout on TTY' do
        expect { cli.test('config.yml') }.to output(/✓ Schema valid/).to_stdout
      end

      it 'passes config through to stdout when piped from stdin' do
        allow($stdout).to receive(:tty?).and_return(false)
        allow($stdin).to receive(:read).and_return("channel:\n  url: https://example.com\n")
        expect { cli.test('-') }.to output("channel:\n  url: https://example.com\n").to_stdout
      end

      it 'supports --json output' do
        expect { cli.invoke(:test, ['config.yml'], { json: true }) }.to output(/"success": true/).to_stdout
      end

      it 'prints result.rss for --xml without a second Html2rss.feed call', :aggregate_failures do
        allow(Html2rss).to receive(:feed)
        expect { cli.invoke(:test, ['config.yml'], { xml: true }) }
          .to output(%r{<rss/>}).to_stdout
        expect(Html2rss).not_to have_received(:feed)
      end

      it 'forwards --min-items 0 to Html2rss.test' do # rubocop:disable RSpec/ExampleLength
        allow(Html2rss).to receive(:test).and_return(test_result_success)

        cli.invoke(:test, ['config.yml'], { min_items: 0 })

        expect(Html2rss).to have_received(:test).with(
          'config.yml',
          nil,
          hash_including(min_items: 0)
        )
      end

      it 'forwards --strict-quality to Html2rss.test' do # rubocop:disable RSpec/ExampleLength
        allow(Html2rss).to receive(:test).and_return(test_result_success)

        cli.invoke(:test, ['config.yml'], { strict_quality: true })

        expect(Html2rss).to have_received(:test).with(
          'config.yml',
          nil,
          hash_including(strict_quality: true)
        )
      end

      it 'forwards --compare-enhance to Html2rss.test', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        allow(Html2rss).to receive(:test).and_return(test_result_success)

        cli.invoke(:test, ['config.yml'], { compare_enhance: true })

        expect(Html2rss).to have_received(:test).with(
          'config.yml',
          nil,
          hash_including(compare_enhance: true)
        )
      end
    end

    context 'when test fails' do
      before do
        allow(Html2rss).to receive(:test).and_return(test_result_failure)
      end

      it 'raises a Thor::Error on failure' do
        expect { cli.test('config.yml') }
          .to raise_error(Thor::Error, /Extracted 0 items/)
      end

      it 'supports --quiet when test fails' do
        expect { cli.invoke(:test, ['config.yml'], { quiet: true }) }
          .to output(/Extracted 0 items/).to_stderr
          .and raise_error(Thor::Error)
      end
    end
  end

  describe '#mcp' do
    before do
      allow(Html2rss::MCP).to receive(:start)
    end

    it 'starts the MCP server with stdio transport by default' do
      cli.invoke(:mcp, [])

      expect(Html2rss::MCP).to have_received(:start).with(transport: :stdio, port: 8080)
    end

    it 'starts the MCP server with HTTP transport when specified' do
      cli.invoke(:mcp, [], { transport: 'http', port: 4010 })

      expect(Html2rss::MCP).to have_received(:start).with(transport: :http, port: 4010)
    end
  end

  describe '#validate' do
    let(:result_success) { instance_double(Dry::Validation::Result, success?: true, errors: {}) }
    let(:result_failure) { instance_double(Dry::Validation::Result, success?: false, errors: { selectors: ['bad config'] }) }

    context 'when the config is valid' do
      before do
        allow(Html2rss).to receive(:validate).and_return(result_success)
      end

      it 'prints confirmation' do
        expect { cli.validate('config.yml') }.to output(/Configuration is valid/).to_stdout
      end

      it 'validates from stdin (-)' do
        allow($stdin).to receive(:read).and_return("channel:\n  url: https://example.com\n")
        expect { cli.validate('-') }.to output(/Configuration is valid/).to_stdout
      end

      it 'validates multiple files with ok indicators' do
        expect { cli.validate('spec/fixtures/single.test.yml', 'spec/fixtures/feeds.test.yml') }
          .to output(%r{ok\s+spec/fixtures/single\.test\.yml}).to_stdout
      end
    end

    context 'when the config is invalid' do
      before do
        allow(Html2rss).to receive(:validate).and_return(result_failure)
      end

      it 'raises a CLI error with details' do
        expect { cli.validate('config.yml') }
          .to raise_error(Thor::Error, /Invalid configuration/)
      end

      it 'raises a CLI error summarizing multiple file failures' do
        expect { cli.validate('spec/fixtures/single.test.yml', 'spec/fixtures/feeds.test.yml') }
          .to raise_error(Thor::Error, %r{2/2 configurations failed validation})
      end
    end
  end

  describe '#scrape' do
    let(:rss_xml) { '<rss><channel><title>Example</title></channel></rss>' }
    let(:feed_res) do
      instance_double(
        Html2rss::FeedResult,
        to_rss: rss_xml,
        to_json_feed: { title: 'Example', items: [] },
        status: instance_double(Html2rss::Status, to_h: {})
      )
    end

    before do
      allow(Html2rss).to receive(:scrape).and_return(feed_res)
    end

    it 'prints RSS to stdout' do
      expect { cli.scrape('https://example.com/news') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'supports --format jsonfeed and --explain' do
      expect { cli.invoke(:scrape, ['https://example.com/news'], { format: 'jsonfeed', explain: true }) }
        .to output(/"title": "Example"/).to_stdout
    end
  end

  describe '#schema' do
    it 'prints JSON schema to stdout' do
      expect { cli.schema }.to output(/http-schema-url|\$schema/).to_stdout
    end

    it 'writes schema to file with --write', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Dir.mktmpdir do |dir|
        target_file = File.join(dir, 'schema.json')
        expect { cli.invoke(:schema, [], { write: target_file }) }
          .to output(/schema\.json/).to_stdout
        expect(File.read(target_file)).to include('$schema')
      end
    end
  end
end
