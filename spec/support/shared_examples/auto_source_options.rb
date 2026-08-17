# frozen_string_literal: true

RSpec.shared_examples 'auto source option forwarding' do |method:|
  let(:url) { 'https://www.welt.de/' }
  let(:feed_result) do
    instance_double(Html2rss::FeedResult, to_rss: nil, to_json_feed: nil)
  end

  before do
    allow(described_class).to receive(:feed_result).and_return(feed_result)
  end

  it 'forwards items_selector into selectors.items with enhance' do
    described_class.public_send(method, url, items_selector: '.css.selector')

    expect(described_class).to have_received(:feed_result).with(
      hash_including(selectors: { items: { selector: '.css.selector', enhance: true } })
    )
  end

  it 'omits strategy and defaults max_requests to 4', :aggregate_failures do
    described_class.public_send(method, url)

    expect(described_class).to have_received(:feed_result).with(hash_excluding(:strategy))
    expect(described_class).to have_received(:feed_result).with(
      hash_including(request: hash_including(max_requests: 4))
    )
  end

  it 'forwards max_redirects into request' do
    described_class.public_send(method, url, max_redirects: 8)

    expect(described_class).to have_received(:feed_result).with(
      hash_including(request: hash_including(max_redirects: 8))
    )
  end

  it 'forwards max_requests into request' do
    described_class.public_send(method, url, max_requests: 8)

    expect(described_class).to have_received(:feed_result).with(
      hash_including(request: hash_including(max_requests: 8))
    )
  end
end
