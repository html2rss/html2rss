# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ResponseGuard do
  subject(:guard) { described_class.new(policy:) }

  let(:policy) do
    Html2rss::RequestService::Policy.new(
      max_response_bytes: 5,
      max_decompressed_bytes: 8
    )
  end

  describe '#inspect_chunk!' do
    it 'raises when the streamed size exceeds the policy' do
      expect do
        guard.inspect_chunk!(total_bytes: 6, headers: { 'content-length' => '6' })
      end.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 5 bytes')
    end
  end

  describe '#inspect_body!' do
    it 'raises when the final body exceeds the decompressed limit' do
      expect do
        guard.inspect_body!('123456789')
      end.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 8 bytes')
    end
  end
end
