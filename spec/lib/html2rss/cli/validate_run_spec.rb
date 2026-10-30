# frozen_string_literal: true

RSpec.describe Html2rss::CLI::Validate do
  # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups -- one shared fixture set
  let(:success) { Html2rss::Config::ValidationReport.ok }
  let(:issue) { Html2rss::Config::ValidationIssue.new(path: %i[selectors], code: :invalid_value, message: 'bad') }
  let(:failure) { Html2rss::Config::ValidationReport.failure([issue]) }
  let(:single) { 'spec/fixtures/single.test.yml' }
  let(:feeds) { 'spec/fixtures/feeds.test.yml' }
  let(:report) { success }

  before { allow(Html2rss).to receive(:validate).and_return(report) }

  describe '.run' do
    describe 'a single file' do
      it 'confirms validity', :aggregate_failures do
        expect { described_class.run([single], params: { 'a' => 'b' }, quiet: false) }
          .to output("Configuration is valid\n").to_stdout
        expect(Html2rss).to have_received(:validate).with(single, params: { 'a' => 'b' })
      end

      it 'stays silent when quiet' do
        expect { described_class.run([single], params: {}, quiet: true) }.not_to output.to_stdout
      end

      context 'when invalid' do
        let(:report) { failure }

        it 'raises the formatted report' do
          expect { described_class.run([single], params: {}, quiet: true) }
            .to raise_error(Thor::Error, "Invalid configuration: #{failure}")
        end
      end
    end

    describe 'several files' do
      it 'prints an ok line per file and nothing when quiet', :aggregate_failures do
        expect { described_class.run([single, feeds], params: {}, quiet: false) }
          .to output("ok   #{single}\nok   #{feeds}\n").to_stdout
        expect { described_class.run([single, feeds], params: {}, quiet: true) }.not_to output.to_stdout
      end

      context 'when some fail' do
        before do
          allow(Html2rss).to receive(:validate).with(single, anything).and_return(success)
          allow(Html2rss).to receive(:validate).with(feeds, anything).and_return(failure)
        end

        it 'lists failures through warn and raises a summary', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          allow(described_class).to receive(:warn)

          expect do
            expect { described_class.run([single, feeds], params: {}, quiet: false) }
              .to raise_error(Thor::Error, '1/2 configurations failed validation.')
          end.to output("ok   #{single}\n").to_stdout
          expect(described_class).to have_received(:warn).with("FAIL #{feeds}").ordered
          expect(described_class).to have_received(:warn).with("       #{issue}").ordered
        end
      end
    end

    describe 'a config file followed by a feed name' do
      it 'validates the named feed', :aggregate_failures do
        expect { described_class.run([feeds, 'notitle'], params: { 'p' => '1' }, quiet: false) }
          .to output("Configuration is valid\n").to_stdout
        expect(Html2rss).to have_received(:validate).with(feeds, 'notitle', params: { 'p' => '1' })
      end

      it 'stays silent when quiet' do
        expect { described_class.run([feeds, 'notitle'], params: {}, quiet: true) }.not_to output.to_stdout
      end

      context 'when the named feed is invalid' do
        let(:report) { failure }

        it 'raises the formatted report' do
          expect { described_class.run([feeds, 'notitle'], params: {}, quiet: true) }
            .to raise_error(Thor::Error, "Invalid configuration: #{failure}")
        end
      end

      %w[missing.yml missing.yaml dir/missing -glob missing* a/b].each do |second|
        it "treats #{second.inspect} as a missing config path" do
          expect { described_class.run([feeds, second], params: {}, quiet: false) }
            .to raise_error(Thor::Error, "No such file: #{second}")
        end
      end

      it 'validates two existing files as a list' do
        expect { described_class.run([single, feeds], params: {}, quiet: false) }.to output(/ok   /).to_stdout
      end

      it 'validates two paths as a list when the first is not a file', :aggregate_failures do
        expect { described_class.run(%w[missing-one notitle], params: {}, quiet: false) }
          .to output("ok   missing-one\nok   notitle\n").to_stdout
      end
    end

    describe 'stdin' do
      before { allow($stdin).to receive(:read).and_return('from: stdin') }

      it 'validates stdin content for no files and for a dash', :aggregate_failures do
        expect { described_class.run([], params: {}, quiet: false) }.to output("Configuration is valid\n").to_stdout
        expect { described_class.run(['-'], params: {}, quiet: false) }.to output("Configuration is valid\n").to_stdout
        expect(Html2rss).to have_received(:validate).with('from: stdin', params: {}).twice
      end
    end
  end

  describe '.resolve_files' do
    it 'keeps the stdin marker only for no files or a lone dash', :aggregate_failures do
      expect(described_class.resolve_files([])).to eq(['-'])
      expect(described_class.resolve_files(['-'])).to eq(['-'])
      expect(described_class.resolve_files(['-', 'spec/fixtures/single.test.yml'])).to eq(
        ['-', 'spec/fixtures/single.test.yml']
      )
    end

    it 'expands globs, keeps unmatched literals and removes duplicates', :aggregate_failures do
      expect(described_class.resolve_files(['spec/fixtures/*.test.yml'])).to include(single, feeds)
      expect(described_class.resolve_files(%w[nothing-here nothing-here])).to eq(['nothing-here'])
      expect(described_class.resolve_files([single, 'spec/fixtures/single.test.*'])).to eq([single])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
end
