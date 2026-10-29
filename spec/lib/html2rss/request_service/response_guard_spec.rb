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

  describe '#inspect_body!' do
    let(:blocked_body) do
      fixture = Pathname(__dir__).join('../../../fixtures/challenge/cloudflare_interstitial.html').expand_path
      raise "challenge fixture missing at #{fixture}" unless fixture.file?

      fixture.read
    end

    let(:nginx_403_body) do
      <<~HTML
        <html>
        <head><title>403 Forbidden</title></head>
        <body>
        <center><h1>403 Forbidden</h1></center>
        <hr><center>nginx</center>
        </body>
        </html>
      HTML
    end

    it 'raises when the final body exceeds the decompressed limit' do
      expect do
        guard.inspect_body!('x' * 1_001)
      end.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 1000 bytes')
    end

    it 'raises when the body matches an anti-bot interstitial signature' do # rubocop:disable RSpec/ExampleLength
      expect { guard.inspect_body!(blocked_body) }
        .to raise_error(
          Html2rss::RequestService::BlockedSurfaceDetected,
          'Blocked surface detected: Cloudflare anti-bot interstitial page. ' \
          'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, or run from an ' \
          'environment that can complete anti-bot checks.'
        )
    end

    it 'raises when the body matches an nginx 403 Forbidden block page' do # rubocop:disable RSpec/ExampleLength
      expect { guard.inspect_body!(nginx_403_body) }
        .to raise_error(
          Html2rss::RequestService::BlockedSurfaceDetected,
          'Blocked surface detected: HTTP 403 Forbidden access block page. ' \
          'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, or run from an ' \
          'environment that is not IP-blocked.'
        )
    end

    it 'does not raise when only one marker appears' do
      expect { guard.inspect_body!('<html><title>Just a moment...</title></html>') }.not_to raise_error
    end

    it 'treats a nil body as empty' do
      expect { guard.inspect_body!(nil) }.not_to raise_error
    end
  end
end
