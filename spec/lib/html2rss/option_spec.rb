# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Option do
  describe '.integer' do
    it 'returns an Integer inside the inclusive bounds', :aggregate_failures do
      expect(described_class.integer(:n, 1, min: 1, max: 3)).to eq(1)
      expect(described_class.integer(:n, 3, min: 1, max: 3)).to eq(3)
      expect(described_class.integer(:n, 99, min: 1)).to eq(99)
    end

    it 'passes nil only when optional', :aggregate_failures do
      expect(described_class.integer(:n, nil, min: 1, optional: true)).to be_nil
      expect { described_class.integer(:n, nil, min: 1) }.to raise_error(Html2rss::InvalidOption, /got nil/)
    end

    it 'rejects out-of-range values naming the option and bounds', :aggregate_failures do
      expect { described_class.integer(:limit, 0, min: 1, max: 3) }
        .to raise_error(Html2rss::InvalidOption, 'limit must be an Integer in 1..3, got 0')
      expect { described_class.integer(:limit, 4, min: 1, max: 3) }.to raise_error(Html2rss::InvalidOption)
    end

    it 'rejects non-Integer values', :aggregate_failures do
      ['5', 2.0, :a, true].each do |value|
        expect { described_class.integer(:n, value, min: 1) }.to raise_error(Html2rss::InvalidOption)
      end
    end
  end

  describe '.strategy' do
    it 'maps nil to :auto and symbolizes strings', :aggregate_failures do
      expect(described_class.strategy(nil)).to eq(:auto)
      expect(described_class.strategy('default')).to eq(:default)
      expect(described_class.strategy(:botasaurus)).to eq(:botasaurus)
    end

    it 'rejects unknown and non-name values listing the accepted names', :aggregate_failures do
      expect { described_class.strategy('nope') }.to raise_error(Html2rss::InvalidOption, /one of auto, .*"nope"/)
      [1, [], {}].each do |value|
        expect { described_class.strategy(value) }.to raise_error(Html2rss::InvalidOption)
      end
    end
  end

  describe '.list' do
    it 'returns a non-empty Array' do
      expect(described_class.list(:urls, %w[a])).to eq(%w[a])
    end

    it 'rejects empty, nil and non-Array values', :aggregate_failures do
      [[], nil, 'a', 1..2].each do |value|
        expect do
          described_class.list(:urls, value)
        end.to raise_error(Html2rss::InvalidOption, /urls must be a non-empty/)
      end
    end
  end
end
