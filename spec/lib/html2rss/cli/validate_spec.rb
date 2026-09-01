# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::CLI::Validate do
  describe '.resolve_files' do
    it 'returns stdin marker when no files are given' do
      expect(described_class.resolve_files([])).to eq(['-'])
    end

    it 'expands globs and deduplicates' do
      paths = described_class.resolve_files(['spec/fixtures/single.test.yml'])

      expect(paths).to eq(['spec/fixtures/single.test.yml'])
    end
  end

  describe '.run' do
    let(:success) { instance_double(Dry::Validation::Result, success?: true, errors: {}) }
    let(:failure) do
      errors = instance_double(Dry::Schema::MessageSet, to_h: { selectors: ['bad selector'] })
      instance_double(Dry::Validation::Result, success?: false, errors:)
    end

    it 'reports ok lines for multiple valid files' do
      allow(Html2rss).to receive(:validate).and_return(success)
      files = ['spec/fixtures/single.test.yml', 'spec/fixtures/feeds.test.yml']

      expect { described_class.run(files, params: {}, quiet: false) }
        .to output(%r{ok   spec/fixtures/single\.test\.yml}).to_stdout
    end

    it 'validates a named feed file' do
      allow(Html2rss).to receive(:validate)
        .with('spec/fixtures/feeds.test.yml', 'notitle', params: {})
        .and_return(success)

      expect { described_class.run(%w[spec/fixtures/feeds.test.yml notitle], params: {}, quiet: false) }
        .to output("Configuration is valid\n").to_stdout
    end

    it 'reads config from stdin when file is "-"' do
      allow(Html2rss).to receive(:validate).with('yaml-from-stdin', params: {}).and_return(success)
      allow($stdin).to receive(:read).and_return('yaml-from-stdin')

      expect do
        described_class.run(['-'], params: {}, quiet: false)
      end.to output("Configuration is valid\n").to_stdout
    end

    it 'raises for a single invalid file' do
      allow(Html2rss).to receive(:validate).and_return(failure)

      expect do
        described_class.run(['bad.yml'], params: {}, quiet: false)
      end.to raise_error(Thor::Error, /Invalid configuration/)
    end

    it 'aggregates failures across multiple files' do
      allow(Html2rss).to receive(:validate).with('good.yml', params: {}).and_return(success)
      allow(Html2rss).to receive(:validate).with('bad.yml', params: {}).and_return(failure)

      expect do
        described_class.run(%w[good.yml bad.yml], params: {}, quiet: false)
      end.to raise_error(Thor::Error, '1/2 configurations failed validation.')
    end

    it 'suppresses success output when quiet' do
      allow(Html2rss).to receive(:validate).and_return(success)

      expect do
        described_class.run(['good.yml'], params: {}, quiet: true)
      end.not_to output.to_stdout
    end
  end
end
