# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline::AutoFallback do
  describe '::NON_FALLBACK_ERRORS' do
    it 'includes Faraday RedirectLimitReached' do
      expect(described_class::NON_FALLBACK_ERRORS)
        .to include(Faraday::FollowRedirects::RedirectLimitReached)
    end

    it 'does not abort auto when Faraday reports an unsupported content type' do
      expect(described_class::NON_FALLBACK_ERRORS)
        .not_to include(Html2rss::RequestService::UnsupportedResponseContentType)
    end
  end
end
