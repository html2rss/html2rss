# frozen_string_literal: true

require 'tmpdir'
require_relative '../../support/saved_responses'

RSpec.describe SavedResponses do
  let(:dir) { File.expand_path('../../fixtures/auto_source/saved_responses', __dir__) }
  let(:page) { File.join(dir, 'page.html') }
  let(:page_url) { 'https://example.com/news/' }
  let(:session) { described_class.new(dir) }

  def article_urls(request_session: nil)
    AutoSourceCorpus.auto_source(path: page, url: page_url, request_session:).articles.map { _1.url.to_s }
  end

  it 'yields only HTML tier items without a request session' do
    expect(article_urls).to eq(%w[https://example.com/news/html-first https://example.com/news/html-second
                                  https://example.com/news/html-third])
  end

  it 'serves the native feed tier from the saved feed' do
    expect(article_urls(request_session: session)).to include('https://example.com/news/feed-first',
                                                              'https://example.com/news/feed-second')
  end

  it 'answers a saved url with a 200 feed response' do
    response = session.follow_up(url: 'https://example.com/news/feed.xml', relation: :auto_source,
                                 origin_url: page_url)

    expect(response).to have_attributes(status: 200, feed_response?: true)
  end

  it 'fails an unmapped url like an unreachable host, never touching the network', :aggregate_failures do
    allow(Html2rss::RequestService).to receive(:execute).and_call_original

    expect { session.follow_up(url: 'https://example.com/other', relation: :auto_source, origin_url: page_url) }
      .to raise_error(Html2rss::RequestService::ConnectionFailed, /no saved response/)
    expect(Html2rss::RequestService).not_to have_received(:execute)
  end

  it 'refuses a saved response on another host as the policy does', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- tmp manifest setup
    Dir.mktmpdir do |other|
      File.write(File.join(other, RevisionComparison::MANIFEST), "feed.xml\thttps://feeds.example.net/show.xml\n")
      saved = described_class.new(other)

      expect { saved.follow_up(url: 'https://feeds.example.net/show.xml', relation: :auto_source, origin_url: page_url) }
        .to raise_error(Html2rss::RequestService::CrossOriginFollowUpDenied)
    end
  end

  it 'serves a saved feed on another host that the page advertises' do # rubocop:disable RSpec/ExampleLength -- tmp manifest + proof setup
    advertisement = Html2rss::RequestService::FeedAdvertisement.from_document(
      Nokogiri::HTML('<head><link rel="alternate" type="application/rss+xml" href="https://feeds.example.net/show.xml"></head>'),
      page_url:
    )
    Dir.mktmpdir do |other|
      FileUtils.cp(File.join(dir, 'feed.xml'), other)
      File.write(File.join(other, RevisionComparison::MANIFEST), "feed.xml\thttps://feeds.example.net/show.xml\n")

      response = described_class.new(other).follow_up(
        url: 'https://feeds.example.net/show.xml', relation: :advertised_feed, origin_url: page_url, advertisement:
      )

      expect(response).to have_attributes(status: 200, feed_response?: true)
    end
  end

  it 'skips the native feed tier when its url is not saved' do
    Dir.mktmpdir do |empty|
      File.write(File.join(empty, RevisionComparison::MANIFEST), "feed.xml\thttps://example.com/elsewhere.xml\n")

      expect(article_urls(request_session: described_class.new(empty))).to eq(article_urls)
    end
  end
end
