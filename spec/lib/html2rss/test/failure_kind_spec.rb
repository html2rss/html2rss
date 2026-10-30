# frozen_string_literal: true

RSpec.describe Html2rss::Test::FailureKind do
  let(:predicates) { %i[schema? execution? min_items? quality?] }

  describe '.[]' do
    it 'rejects unknown names with the offending name' do
      expect { described_class[:timeout] }.to raise_error(ArgumentError, 'unknown failure kind: :timeout')
    end

    it 'returns the same instance for symbol and string names', :aggregate_failures do
      expect(described_class[:schema]).to be(described_class['schema'])
      expect { described_class.new(name: :schema) }.to raise_error(NoMethodError)
    end
  end

  describe 'predicates' do
    %i[schema execution min_items quality].each do |kind|
      it "is true only for #{kind}" do
        flags = predicates.to_h { |predicate| [predicate, described_class[kind].public_send(predicate)] }

        expect(flags.select { |_, value| value }.keys).to eq([:"#{kind}?"])
      end
    end
  end

  describe '#to_sym' do
    it 'returns the name symbol' do
      expect(described_class['min_items'].to_sym).to be(:min_items)
    end
  end

  describe '#to_s' do
    it 'returns the name string' do
      expect(described_class[:quality].to_s).to eq('quality')
    end
  end
end
