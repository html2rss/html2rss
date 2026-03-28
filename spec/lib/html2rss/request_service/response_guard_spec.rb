# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ResponseGuard do
  subject(:guard) { described_class.new(policy:) }

  let(:policy) do
    Html2rss::RequestService::Policy.new(
      max_response_bytes: 1_000,
      max_decompressed_bytes: 1_000
    )
  end

  describe '#inspect_chunk!' do
    it 'raises when the streamed size exceeds the policy' do
      expect do
        guard.inspect_chunk!(total_bytes: 1_001, headers: { 'content-length' => '1_001' })
      end.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 1000 bytes')
    end
  end

  describe '#inspect_body!' do
    let(:blocked_body) do
      '<html><head><title>Just a moment...</title></head>' \
        '<body>Checking your browser before accessing openai.com.</body></html>'
    end

    it 'raises when the final body exceeds the decompressed limit' do
      expect do
        guard.inspect_body!('x' * 1_001)
      end.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 1000 bytes')
    end

    it 'raises when the body matches an anti-bot interstitial signature' do
      expect { guard.inspect_body!(blocked_body) }
        .to raise_error(Html2rss::RequestService::BlockedSurfaceDetected,
                        /Blocked surface detected: Cloudflare anti-bot interstitial page/)
    end

    it 'does not raise when only one marker appears' do
      expect { guard.inspect_body!('<html><title>Just a moment...</title></html>') }.not_to raise_error
    end
  end
end
