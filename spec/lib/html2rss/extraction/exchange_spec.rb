# frozen_string_literal: true

RSpec.describe Html2rss::Extraction::Exchange do
  subject(:exchange) { described_class.new(responses:, cap: 2) }

  let(:responses) { {} }
  let(:ask) do
    lambda do |path = 'feed', relation: :auto_source|
      exchange.follow_up(url: "https://example.com/#{path}", relation:, origin_url: 'https://example.com/')
    end
  end

  describe '#follow_up' do
    it 'replays an answered request as a response' do
      responses['auto_source https://example.com/feed'] =
        { url: 'https://example.com/feed', status: 200, headers: { 'content-type' => 'application/rss+xml' }, body: '<rss/>' }

      expect(ask.call).to have_attributes(body: '<rss/>', status: 200, feed_response?: true)
    end

    it 'records an unanswered request and ends the pass', :aggregate_failures do
      expect(exchange.guard { ask.call && :reached }).to be_nil
      expect(exchange.requests.map(&:to_h)).to eq(
        [{ id: 'auto_source https://example.com/feed', url: 'https://example.com/feed', relation: :auto_source,
           origin_url: 'https://example.com/' }]
      )
    end

    it 'keys a request by its relation and URL' do
      exchange.guard { ask.call(relation: :advertised_feed) }

      expect(exchange.requests.map(&:id)).to eq(['advertised_feed https://example.com/feed'])
    end

    it 'replays a failure as an error of its kind', :aggregate_failures do
      responses['auto_source https://example.com/feed'] = { error_kind: :timeout }
      responses['auto_source https://example.com/full'] = { error_kind: :budget }

      expect { ask.call }.to raise_error(described_class::RequestFailed) { |error| expect(error.kind).to eq(:timeout) }
      expect { ask.call('full') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
    end

    it 'refuses a request beyond the cap', :aggregate_failures do
      %w[a b].each { |path| exchange.guard { ask.call(path) } }

      expect { ask.call('c') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
      expect(exchange.requests.map(&:url)).to eq(%w[https://example.com/a https://example.com/b])
    end
  end
end
