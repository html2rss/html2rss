# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestControls do
  describe '.from_config' do
    let(:symbol_config) { { strategy: :browserless, request: { max_redirects: 3, max_requests: 9 } } }

    it 'extracts explicit controls from symbol-keyed config', :aggregate_failures do
      controls = described_class.from_config(symbol_config)

      expect(controls).to have_attributes(strategy: :browserless, max_redirects: 3, max_requests: 9)
      explicit_keys = %i[strategy max_redirects max_requests].select { controls.explicit?(_1) }
      expect(explicit_keys).to eq(%i[strategy max_redirects max_requests])
    end

    it 'raises when top-level keys are not symbols' do
      expect do
        described_class.from_config('strategy' => :faraday)
      end.to raise_error(ArgumentError, /config must use symbol keys/)
    end

    it 'raises when request keys are not symbols' do
      expect do
        described_class.from_config(request: { 'max_requests' => 4 })
      end.to raise_error(ArgumentError, /config\[:request\] must use symbol keys/)
    end
  end

  describe '#apply_to' do
    it 'writes explicit request controls into the nested request config', :aggregate_failures do
      controls = described_class.new(max_requests: 4, explicit_keys: [:max_requests])
      config = {}

      result = controls.apply_to(config)

      expect(result).to equal(config)
      expect(config).to eq(request: { max_requests: 4 })
    end

    it 'raises a clear error when request config is not a hash' do
      controls = described_class.new(max_requests: 4, explicit_keys: [:max_requests])
      config = { request: 'invalid' }

      expect { controls.apply_to(config) }.to raise_error(ArgumentError, 'request config must be a hash')
    end
  end
end
