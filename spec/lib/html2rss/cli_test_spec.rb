# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::CLI, '#test' do
  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers -- CLI option wiring contracts
  let(:success) { true }
  let(:error_message) { nil }
  let(:result) do
    Html2rss::Test::Result.new(
      success:, item_count: 1, sample_items: [], channel_title: 'T', channel_url: 'https://a.test',
      strategy_used: :default, duration_seconds: 0.5, validation_issues: nil, error_message:, failure_kind: nil,
      rss: '<rss/>'
    )
  end
  let(:run_test) { ->(args, options = {}) { described_class.new.invoke(:test, args, options) } }
  let(:tty) { true }

  before do
    allow(Html2rss).to receive(:test).and_return(result)
    allow($stdout).to receive(:tty?).and_return(tty)
  end

  it 'forwards the documented defaults to Html2rss.test' do
    run_test.call(['cfg: 1'])

    expect(Html2rss).to have_received(:test).with(
      'cfg: 1', nil, min_items: 1, params: {}, strategy: nil, strict_quality: false, compare_enhance: false
    )
  end

  it 'forwards the feed name, params, strategy and flags' do
    run_test.call(
      ['cfg: 1', 'feed'],
      { params: { 'a' => 'b' }, strategy: 'botasaurus', min_items: 3, strict_quality: true, compare_enhance: true }
    )

    expect(Html2rss).to have_received(:test).with(
      'cfg: 1', 'feed', min_items: 3, params: { 'a' => 'b' }, strategy: 'botasaurus', strict_quality: true,
                        compare_enhance: true
    )
  end

  describe 'config input' do
    it 'reads a file and labels the card with its path', :aggregate_failures do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'c.yml')
        File.write(path, 'from: file')

        expect { run_test.call([path]) }.to output(/Schema valid\S* \(#{Regexp.escape(path)}\)/).to_stdout
        expect(Html2rss).to have_received(:test).with('from: file', nil, hash_including(min_items: 1))
      end
    end

    it 'labels raw strings', :aggregate_failures do
      expect { run_test.call(['raw: yaml']) }.to output(/\(raw_string\)/).to_stdout
    end
  end

  describe 'output modes' do
    it 'prints the result as pretty JSON with --json' do
      expect { run_test.call(['c'], { json: true }) }.to output("#{JSON.pretty_generate(result.to_h)}\n").to_stdout
    end

    it 'prints nothing with --quiet on success', :aggregate_failures do
      expect { run_test.call(['c'], { quiet: true }) }.not_to output.to_stdout
      expect { run_test.call(['c'], { quiet: true }) }.not_to output.to_stderr
    end

    it 'prefers --json over --quiet' do
      expect { run_test.call(['c'], { json: true, quiet: true }) }.to output(/"success": true/).to_stdout
    end

    it 'dumps the rss after the summary with --xml' do
      expect { run_test.call(['c'], { xml: true }) }.to output(%r{Channel: T \(https://a\.test\)\n<rss/>\n\z}).to_stdout
    end

    it 'does not dump the rss without --xml' do
      expect { run_test.call(['c']) }.not_to output(%r{<rss/>}).to_stdout
    end

    context 'when piped from stdin' do
      let(:tty) { false }

      before { allow($stdin).to receive(:read).and_return("channel:\n  url: x\n") }

      it 'echoes the config on success' do
        expect { run_test.call(['-']) }.to output("channel:\n  url: x\n").to_stdout
      end

      it 'prints the summary card instead of echoing with --xml' do
        expect { run_test.call(['-'], { xml: true }) }.to output(/Schema valid/).to_stdout
      end

      it 'prints the card for non-stdin input' do
        expect { run_test.call(['raw: 1']) }.to output(/Schema valid/).to_stdout
      end
    end

    context 'when stdout is a terminal' do
      let(:terminal) { StringIO.new }

      before do
        allow(terminal).to receive(:tty?).and_return(true)
        $stdout = terminal # rubocop:disable RSpec/ExpectOutput -- tty stdout needs a custom IO
        allow($stdin).to receive(:read).and_return('x: 1')
      end

      after { $stdout = STDOUT } # rubocop:disable RSpec/ExpectOutput

      it 'prints the summary card labelled stdin for a dash and for no argument', :aggregate_failures do
        run_test.call(['-'])
        run_test.call([nil])

        expect(terminal.string.scan('Schema valid')).to eq(['Schema valid'] * 2)
        expect(terminal.string.scan('(stdin)').size).to eq(2)
        expect(Html2rss).to have_received(:test).with('x: 1', nil, hash_including(min_items: 1)).twice
      end
    end
  end

  context 'when the test fails' do
    let(:success) { false }
    let(:error_message) { 'boom' }

    it 'raises the error message', :aggregate_failures do
      expect { run_test.call(['c']) }.to raise_error(Thor::Error, 'boom').and output(/Test failed/).to_stderr
    end

    it 'prints only the error with --quiet' do
      expect { run_test.call(['c'], { quiet: true }) }
        .to raise_error(Thor::Error).and output("boom\n").to_stderr
    end

    it 'writes a failure line for piped stdin' do
      allow($stdout).to receive(:tty?).and_return(false)
      allow($stdin).to receive(:read).and_return('x: 1')

      expect { run_test.call(['-']) }
        .to raise_error(Thor::Error).and output("Test failed: boom\n").to_stderr
    end

    it 'does not print the rss with --xml' do
      expect { run_test.call(['c'], { xml: true }) }
        .to raise_error(Thor::Error).and(output('').to_stdout).and output(/Test failed/).to_stderr
    end

    context 'without an error message' do
      let(:error_message) { nil }

      it 'raises a generic failure' do
        expect { run_test.call(['c']) }.to raise_error(Thor::Error, 'Test failed').and output(/Test failed/).to_stderr
      end
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
end
