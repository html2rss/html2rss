# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Substring do
  let(:context) { Html2rss::Selectors::StepEnv.new(step_config:) }

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with end' do
    let(:step_config) { { start: 4, end: 6 } }

    it 'extracts the substring' do
      expect(described_class.new('Foo bar and baz', context).call).to eq 'bar'
    end
  end

  context 'without end' do
    let(:step_config) { { start: 3 } }

    it 'extracts from start to the end of string' do
      expect(described_class.new('foobarbaz', context).call).to eq 'barbaz'
    end
  end

  describe '#range' do
    subject { described_class.new('value', context).range }

    context 'when start and end options are provided' do
      let(:step_config) { { start: 2, end: 4 } }

      it { is_expected.to eq(2..4) }
    end

    context 'when only start option is provided' do
      let(:step_config) { { start: 3 } }

      it { is_expected.to eq(3..) }
    end

    context 'when start and end options are equal' do
      let(:step_config) { { start: 2, end: 2 } }

      it 'raises an ArgumentError' do
        expect { subject }.to raise_error(ArgumentError, 'The `start` value must be unequal to the `end` value.')
      end
    end

    context 'when start option is missing' do
      let(:step_config) { { end: 4 } }

      it 'raises an error' do
        expect { subject }.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                                          /The `start` option is missing/)
      end
    end
  end
end
