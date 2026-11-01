# frozen_string_literal: true

# Mutant binds examples from the described constant, so each error class gets its own top-level describe.
{
  Html2rss::InvalidOption => [:other, false],
  Html2rss::Url::InvalidUrlError => [:invalid_url, false],
  Html2rss::RequestService::UnknownStrategy => [:other, false],
  Html2rss::RequestService::InvalidUrl => [:invalid_url, false],
  Html2rss::RequestService::UnsupportedUrlScheme => [:invalid_url, false],
  Html2rss::RequestService::UnsupportedResponseContentType => [:other, false],
  Html2rss::RequestService::RequestBudgetExceeded => [:budget, false],
  Html2rss::RequestService::PrivateNetworkDenied => [:blocked, false],
  Html2rss::RequestService::CrossOriginFollowUpDenied => [:blocked, false],
  Html2rss::RequestService::ResponseTooLarge => [:budget, false],
  Html2rss::RequestService::RedirectLimitReached => [:budget, false],
  Html2rss::RequestService::BlockedSurfaceDetected => [:blocked, false],
  Html2rss::RequestService::ConnectionFailed => [:connection, true],
  Html2rss::RequestService::RequestTimedOut => [:timeout, true],
  Html2rss::RequestService::BotasaurusConfigurationError => [:other, false],
  Html2rss::RequestService::BotasaurusConnectionFailed => [:connection, true],
  Html2rss::RequestService::BotasaurusServiceError => [:other, false]
}.each do |klass, (kind, retryable)|
  RSpec.describe klass do
    subject(:error) { described_class.new('boom') }

    it "is kind #{kind.inspect}, retryable #{retryable}, message unchanged", :aggregate_failures do
      expect(error.kind).to eq(kind)
      expect(error.retryable?).to be(retryable)
      expect(error.message).to eq('boom')
    end
  end
end

RSpec.describe Html2rss::RequestService do # rubocop:disable RSpec/SpecFilePathFormat
  it 'maps every RequestService error class' do
    classes = described_class.constants.map { |name| described_class.const_get(name) }
                             .select { |const| const.is_a?(Class) && const < Html2rss::Error }
    expect(classes.size).to eq(15)
  end
end
