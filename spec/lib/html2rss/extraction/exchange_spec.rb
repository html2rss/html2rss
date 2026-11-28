# frozen_string_literal: true

RSpec.describe Html2rss::Extraction::Exchange do
  subject(:exchange) { described_class.new(responses:, cap: 2) }

  let(:responses) { {} }
  let(:ask) do
    lambda do |path = 'feed', relation: :auto_source|
      exchange.follow_up(url: "https://example.com/#{path}", relation:, origin_url: Html2rss::Url.from_absolute('https://example.com/'))
    end
  end
  let(:feed_answer) do
    { url: 'https://example.com/feed', status: 200, headers: { 'content-type' => 'application/rss+xml' }, body: '<rss/>' }
  end

  describe '#follow_up' do
    it 'replays an answered request as a response' do
      responses['auto_source https://example.com/feed'] = feed_answer

      expect(ask.call).to have_attributes(url: Html2rss::Url.from_absolute('https://example.com/feed'), body: '<rss/>',
                                          status: 200, headers: feed_answer[:headers])
    end

    it 'replays an answer that carries no headers or status' do
      responses['auto_source https://example.com/feed'] = feed_answer.except(:headers, :status)

      expect(ask.call).to have_attributes(headers: {}, status: nil)
    end

    it 'records an unanswered request and ends the pass', :aggregate_failures do
      expect(exchange.guard { ask.call && :reached }).to be_nil
      expect(exchange.requests.map(&:to_h)).to eq(
        [{ id: 'auto_source https://example.com/feed', url: 'https://example.com/feed', relation: :auto_source,
           origin_url: 'https://example.com/' }]
      )
    end

    it 'keys a request by its relation and normalized URL' do
      exchange.guard { exchange.follow_up(url: 'HTTPS://EXAMPLE.com/feed', relation: :advertised_feed, origin_url: 'https://example.com/') }

      expect(exchange.requests.map(&:id)).to eq(['advertised_feed https://example.com/feed'])
    end

    it 'counts the answered requests against the cap' do
      %w[a b c].each { |path| responses["auto_source https://example.com/#{path}"] = { error_kind: :timeout } }

      expect { ask.call('d') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded,
                                              'Request budget exhausted')
    end

    it 'takes a request already wanted again at the cap' do
      %w[a b a].each { |path| exchange.guard { ask.call(path) } }

      expect(exchange.requests.map(&:url)).to eq(%w[https://example.com/a https://example.com/b])
    end

    %i[timeout budget].each do |kind|
      it "replays a reported #{kind} failure as a request failure of that kind" do
        responses['auto_source https://example.com/feed'] = { error_kind: kind }

        expect { ask.call }.to raise_error(described_class::RequestFailed, /\(#{kind}\)/)
      end
    end

    it 'spends one slot for one URL asked under two relations', :aggregate_failures do
      [['a', :auto_source], ['a', :advertised_feed], ['b', :auto_source]].each do |path, relation|
        exchange.guard { ask.call(path, relation:) }
      end

      expect(exchange.requests.size).to eq(3)
      expect { ask.call('c') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
    end

    it 'refuses a request beyond the cap', :aggregate_failures do
      %w[a b].each { |path| exchange.guard { ask.call(path) } }

      expect { ask.call('c') }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
      expect(exchange.requests.map(&:url)).to eq(%w[https://example.com/a https://example.com/b])
    end
  end
end
