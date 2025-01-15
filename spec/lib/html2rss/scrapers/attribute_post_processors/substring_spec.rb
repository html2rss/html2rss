# frozen_string_literal: true

RSpec.describe Html2rss::Scrapers::AttributePostProcessors::Substring do
  it { expect(described_class).to be < Html2rss::Scrapers::AttributePostProcessors::Base }

  context 'with end' do
    subject { described_class.new('Foo bar and baz', options: { start: 4, end: 6 }).get }

    it { is_expected.to eq 'bar' }
  end

  context 'without end' do
    subject { described_class.new('foobarbaz', options: { start: 3 }).get }

    it { is_expected.to eq 'barbaz' }
  end

  describe '#range' do
    subject { described_class.new('value', options:) }

    context 'when start and end options are provided' do
      let(:options) { { start: 2, end: 4 } }

      it 'returns the correct range' do
        expect(subject.range).to eq(2..4)
      end
    end

    context 'when only start option is provided' do
      let(:options) { { start: 3 } }

      it 'returns the range from start index to the end of the string' do
        expect(subject.range).to eq(3..)
      end
    end

    context 'when start and end options are equal' do
      let(:options) { { start: 2, end: 2 } }

      it 'raises an ArgumentError' do
        expect do
          subject.range
        end.to raise_error(ArgumentError, 'The `start` value must be unequal to the `end` value.')
      end
    end

    context 'when start option is missing' do
      let(:options) { { end: 4 } }

      it 'raises an error' do
        expect { subject.range }.to raise_error(Html2rss::Scrapers::AttributePostProcessors::InvalidType, /but is: NilClass in:/)
      end
    end
  end
end
