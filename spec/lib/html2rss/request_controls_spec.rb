# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestControls do
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
