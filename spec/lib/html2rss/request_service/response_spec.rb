# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Response do
  describe '#headers' do
    subject(:returned_headers) { described_class.new(body: '', headers:).headers }

    let(:headers) do
      { key: 42 }
    end

    it 'returns hash w/ string keys', :aggregate_failures do
      expect(returned_headers).to eq('key' => 42)
      expect(returned_headers).not_to be headers
    end
  end
end
