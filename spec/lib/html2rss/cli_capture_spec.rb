# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::CLI, '#capture' do
  # rubocop:disable RSpec/ExampleLength -- CLI option wiring contracts
  let(:native_feed) { nil }
  let(:capture_result) do
    Html2rss::Capture::CaptureResult.new(
      config: { channel: { url: 'https://www.example.com/blog' } }, yaml: "yaml: 1\n", articles_count: 5,
      channel_title: 'Example', has_selectors: true, segment_strategy: :list, selected_strategy: nil,
      inferred_topics: %w[tech], native_feed:, admission_drops: { a: 1 }
    )
  end
  let(:run_capture) { ->(args, options = {}) { described_class.new.invoke(:capture, args, options) } }

  before { allow(Html2rss::Capture).to receive(:build).and_return(capture_result) }

  it 'forwards the documented defaults', :aggregate_failures do
    run_capture.call(['https://example.com'])

    expect(Html2rss::Capture).to have_received(:build).with(
      'https://example.com', strategy: :auto, items_selector: nil, topics: nil, title: nil, summary: nil,
                             force: false, enhance: nil, limit: nil, max_redirects: nil, max_requests: nil,
                             local_file_path: nil
    )
  end

  it 'forwards every option', :aggregate_failures do
    run_capture.call(
      ['https://example.com'],
      { strategy: 'default', items_selector: '.card', topics: ' tech , jobs,culture', title: 'T', summary: 'S',
        force: true, enhance: false, limit: 7, max_redirects: 2, max_requests: 3 }
    )

    expect(Html2rss::Capture).to have_received(:build).with(
      'https://example.com', strategy: :default, items_selector: '.card', topics: %w[tech jobs culture], title: 'T',
                             summary: 'S', force: true, enhance: false, limit: 7, max_redirects: 2, max_requests: 3,
                             local_file_path: nil
    )
  end

  describe '--input' do
    let(:dir) { Dir.mktmpdir }
    let(:path) do
      File.join(dir, 'p.html').tap do |file|
        File.write(file, '<html><head><link rel="canonical" href="https://canon.test/x"></head></html>')
      end
    end

    after { FileUtils.remove_entry(dir) }

    it 'captures the local file with the local_file strategy and the detected url', :aggregate_failures do
      run_capture.call([nil], { input: path, strategy: 'default' })

      expect(Html2rss::Capture).to have_received(:build).with(
        'https://canon.test/x', hash_including(strategy: :local_file, local_file_path: File.expand_path(path))
      )
    end

    it 'prefers an explicit url over detection' do
      run_capture.call(['https://given.test'], { input: path })

      expect(Html2rss::Capture).to have_received(:build).with('https://given.test',
                                                              hash_including(strategy: :local_file))
    end

    it 'reports a missing file' do
      expect { run_capture.call([nil], { input: '/nonexistent.html' }) }
        .to raise_error(Thor::Error, 'Input file does not exist: /nonexistent.html')
    end

    it 'asks for a url when none can be detected', :aggregate_failures do
      File.write(path, '<html></html>')

      expect { run_capture.call([nil], { input: path }) }.to raise_error(
        Thor::Error,
        'Could not auto-detect a base URL from HTML metadata. ' \
        'Please specify a URL: html2rss <command> [URL] --input <file>'
      )
    end
  end

  it 'requires a url without --input' do
    expect { run_capture.call([nil]) }.to raise_error(Thor::Error, 'A URL is required unless --input is specified')
  end

  describe 'native feeds' do
    let(:native_feed) { 'https://example.com/feed.xml' }

    it 'warns and exits with status 3 without --force', :aggregate_failures do
      expect { run_capture.call(['https://example.com']) }
        .to output('First-party RSS/Atom feed detected at https://example.com/feed.xml. ' \
                   "Use --force to capture anyway.\n").to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(3) }
    end

    it 'prints the yaml with --force' do
      expect { run_capture.call(['https://example.com'], { force: true }) }.to output("yaml: 1\n").to_stdout
    end
  end

  describe 'output destinations' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it 'writes <domain>/index.yml without a www prefix for --output-dir', :aggregate_failures do
      expect { run_capture.call(['https://www.example.com/blog'], { output_dir: dir }) }
        .to output("Wrote captured config to #{File.join(dir, 'example.com', 'index.yml')}\n").to_stdout
      expect(File.read(File.join(dir, 'example.com', 'index.yml'))).to eq("yaml: 1\n")
    end

    it 'writes to --write, creating parent directories', :aggregate_failures do
      target = File.join(dir, 'nested', 'out.yml')

      expect { run_capture.call(['https://example.com'], { write: target }) }
        .to output("Wrote captured config to #{target}\n").to_stdout
      expect(File.read(target)).to eq("yaml: 1\n")
    end

    it 'prefers --output-dir over --write', :aggregate_failures do
      target = File.join(dir, 'out.yml')
      run_capture.call(['https://example.com'], { output_dir: dir, write: target })

      expect(File).not_to exist(target)
      expect(File).to exist(File.join(dir, 'example.com', 'index.yml'))
    end
  end

  describe '--explain' do
    it 'prints the compact diagnostics payload to stderr' do
      expect { run_capture.call(['https://example.com'], { explain: true }) }.to output(
        "#{JSON.pretty_generate(
          articles_count: 5, channel_title: 'Example', has_selectors: true, segment_strategy: 'list',
          inferred_topics: %w[tech], admission_drops: { a: 1 }
        )}\n"
      ).to_stderr.and output("yaml: 1\n").to_stdout
    end

    it 'prints nothing to stderr otherwise' do
      expect { run_capture.call(['https://example.com']) }.not_to output.to_stderr
    end
  end
  # rubocop:enable RSpec/ExampleLength
end
