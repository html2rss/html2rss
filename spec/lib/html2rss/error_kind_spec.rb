# frozen_string_literal: true

RSpec.describe Html2rss::ErrorKind do
  describe '.[]' do
    it 'returns the same instance per name, accepting strings', :aggregate_failures do
      expect(described_class[:timeout]).to be(described_class['timeout'])
      expect(described_class[:timeout].to_sym).to eq(:timeout)
      expect(described_class[:timeout].to_s).to eq('timeout')
    end

    it 'rejects unknown kinds' do
      expect { described_class[:nope] }.to raise_error(ArgumentError, /unknown error kind: :nope/)
    end

    it 'keeps the closed set stable' do
      expect(described_class::ALL.keys).to eq(%i[timeout blocked connection invalid_url budget other])
    end

    it 'does not allow outside construction' do
      expect { described_class.new(name: :x, retryable: true) }.to raise_error(NoMethodError)
    end
  end

  describe '#retryable?' do
    it 'is true only for timeout and connection', :aggregate_failures do
      retryable = described_class::ALL.select { |_, kind| kind.retryable? }.keys
      expect(retryable).to eq(%i[timeout connection])
    end
  end
end
