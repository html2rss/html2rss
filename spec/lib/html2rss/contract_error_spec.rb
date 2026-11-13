# frozen_string_literal: true

RSpec.describe Html2rss::ContractError do
  let(:contract_errors) do
    [
      Html2rss::Status::InvalidError, Html2rss::FeedResult::InvalidError, Html2rss::SST::InvalidError,
      Html2rss::MCP::Outcome::InvalidError, Html2rss::Article::Enclosure::InvalidError,
      Html2rss::Article::Deduplicator::InvalidError, Html2rss::AutoSource::Segment::InvalidError,
      Html2rss::AutoSource::ScraperContractError, Html2rss::Html::InvalidError,
      Html2rss::RequestService::Context::InvalidError, Html2rss::FeedResolution::InvalidError
    ]
  end

  it { expect(described_class).to be < Html2rss::Error }

  it 'is the base of every wrong-parts and contract error' do
    expect(contract_errors).to all(be < described_class)
  end

  it 'is not an InvalidOption, so CLI option handling never reports it' do
    expect(described_class).not_to be <= Html2rss::InvalidOption
  end
end
