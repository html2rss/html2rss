# frozen_string_literal: true

RSpec.describe Html2rss::Extraction::Exchange do
  subject(:exchange) { described_class.new(responses:, cap: 2) }

  let(:responses) { {} }
  let(:origin) { 'https://example.com/' }
  let(:answer) do
    { url: 'https://example.com/feed', status: 200, headers: { 'content-type' => 'application/rss+xml' }, body: '<rss/>' }
  end

  def follow_up(path = 'feed', relation: :auto_source)
    exchange.follow_up(url: "https://example.com/#{path}", relation:, origin_url: origin)
  end

  describe '#follow_up' do
    it 'replays an answered request as a response', :aggregate_failures do
      responses['auto_source https://example.com/feed'] = answer

      expect(follow_up).to have_attributes(body: '<rss/>', status: 200, url: Html2rss::Url.from_absolute('https://example.com/feed'))
      expect(exchange).not_to be_pending
    end

    it 'records an unanswered request and ends the pass', :aggregate_failures do
      expect(exchange.guard { follow_up && :reached }).to be_nil
      expect(exchange.requests).to eq(
        [described_class::Request.new(id: 'auto_source https://example.com/feed', url: 'https://example.com/feed',
                                      relation: :auto_source, origin_url: origin)]
      )
      expect(exchange).to be_pending
    end

    it 'replays a failure as an error of its kind', :aggregate_failures do
      responses['auto_source https://example.com/feed'] = { error_kind: :timeout }
      responses['auto_source https://example.com/full'] = { error_kind: :budget }

      expect { follow_up }.to raise_error(described_class::RequestFailed) { |error| expect(error.kind).to eq(:timeout) }
      expect { follow_up('full') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
    end

    it 'refuses a request beyond the cap', :aggregate_failures do
      exchange.guard { follow_up('a') }
      exchange.guard { follow_up('b') }

      expect { follow_up('c') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
      expect(exchange.requests.map(&:url)).to eq(%w[https://example.com/a https://example.com/b])
    end

    it 'keys a request by its relation and URL' do
      exchange.guard { follow_up(relation: :advertised_feed) }

      expect(exchange.requests.map(&:id)).to eq(['advertised_feed https://example.com/feed'])
    end
  end

  describe '.fetch' do
    let(:request) do
      described_class::Request.new(id: 'auto_source https://example.com/feed', url: 'https://example.com/feed',
                                   relation: :auto_source, origin_url: origin)
    end
    let(:page) { Html2rss::RequestService::Response.local_html(body: '<html></html>', url: origin) }
    let(:session) { instance_double(Html2rss::RequestSession) }

    it 'answers with the fetched response as plain data' do
      allow(session).to receive(:follow_up).and_return(Html2rss::RequestService::Response.new(**answer, url: Html2rss::Url.from_absolute(answer[:url])))

      expect(described_class.fetch(request, page, session)).to eq(answer)
    end

    it 'reports a failure of the fetch by its kind, and lets a contract error through', :aggregate_failures do
      allow(session).to receive(:follow_up).and_raise(Html2rss::RequestService::RequestTimedOut)

      expect(described_class.fetch(request, page, session)).to eq(error_kind: :timeout)

      allow(session).to receive(:follow_up).and_raise(Html2rss::ContractError)
      expect { described_class.fetch(request, page, session) }.to raise_error(Html2rss::ContractError)
    end

    it 'rebuilds the feed advertisement from the page for an advertised feed' do
      advertising = Html2rss::RequestService::Response.local_html(
        body: '<html><head><link rel="alternate" type="application/rss+xml" href="/feed"></head></html>', url: origin
      )
      allow(session).to receive(:follow_up).and_return(Html2rss::RequestService::Response.local_html(body: '',
                                                                                                     url: origin))

      described_class.fetch(request.with(relation: :advertised_feed), advertising, session)

      expect(session).to have_received(:follow_up)
        .with(hash_including(advertisement: be_a(Html2rss::RequestService::FeedAdvertisement)))
    end
  end
end
