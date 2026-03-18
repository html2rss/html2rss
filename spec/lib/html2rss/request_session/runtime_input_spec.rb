# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::RuntimeInput do
  subject(:runtime_input) { described_class.from_config(config) }

  let(:config) do
    Html2rss::Config.from_hash(
      {
        strategy: :browserless,
        channel: { url: 'https://example.com/blog' },
        selectors: {
          items: { selector: 'article' },
          title: { selector: 'h2' }
        }
      }
    )
  end
  let(:request_policy) { instance_double(Html2rss::RequestService::Policy, max_requests: 7, max_redirects: 8) }

  describe '.from_config' do
    before do
      allow(Html2rss::RequestSession::RuntimePolicy).to receive(:from_config).with(config).and_return(request_policy)
    end

    it 'packages the runtime request inputs for the session', :aggregate_failures do
      expect(runtime_input.url.to_s).to eq('https://example.com/blog')
      expect(runtime_input.headers).to eq(config.headers)
      expect(runtime_input.strategy).to eq(:browserless)
      expect(runtime_input.request_policy).to eq(request_policy)
    end
  end
end
