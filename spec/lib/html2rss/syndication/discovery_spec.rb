# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::Syndication::Discovery do
  describe '.page_dir_paths' do
    it 'returns directory-relative feed guesses for nested pages' do
      expect(described_class.page_dir_paths('https://example.com/news/index.html')).to eq(
        %w[/news/feed /news/rss.xml /news/atom.xml]
      )
    end

    it 'returns no directory guesses for the origin root' do
      expect(described_class.page_dir_paths('https://example.com/')).to eq([])
    end

    it 'returns no directory guesses for a bare origin without a trailing slash' do
      expect(described_class.page_dir_paths('https://example.com')).to eq([])
    end

    it 'uses the root directory for top-level pages', :aggregate_failures do
      expect(described_class.page_dir_paths('https://example.com/index.html')).to eq(
        %w[/feed /rss.xml /atom.xml]
      )
      expect(described_class.page_dir_paths('https://example.com/index.html?page=2')).to eq(
        %w[/feed /rss.xml /atom.xml]
      )
    end
  end

  describe '.candidate_urls' do
    it 'prefers head alternate links from a parsed document before path guesses', :aggregate_failures do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <link rel="alternate" type="application/rss+xml" href="/custom.xml">
        </head></html>
      HTML

      urls = described_class.candidate_urls(
        page_url: 'https://example.com/blog/',
        parsed_body: doc
      )

      expect(urls.first.to_s).to eq('https://example.com/custom.xml')
      expect(urls.map(&:to_s)).to include('https://example.com/feed')
    end

    it 'prefers an alternate whose title or URL hints audio on a podcast page', :aggregate_failures do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <title>Example Show Podcast</title>
          <link rel="alternate" type="application/rss+xml" title="Example &raquo; Feed" href="/feed/">
          <link rel="alternate" type="application/rss+xml" title="Example &raquo; Comments" href="/comments/feed/">
          <link rel="alternate" type="application/rss+xml" title="Show (MP3 Audio)" href="/feed/a/">
          <link rel="alternate" type="application/rss+xml" title="Show" href="/feed/m4a/">
        </head></html>
      HTML

      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: doc).map(&:to_s)

      expect(urls.first(4)).to eq(%w[https://example.com/feed/a/ https://example.com/feed/m4a/
                                     https://example.com/feed/ https://example.com/comments/feed/])
    end

    it 'keeps the first alternate on a news page that also advertises a podcast feed' do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <title>Example Daily: local news</title>
          <meta property="og:type" content="website">
          <link rel="alternate" type="application/rss+xml" title="News" href="/news.xml">
          <link rel="alternate" type="application/rss+xml" title="Morning Podcast" href="/podcast.xml">
          <script type="application/ld+json">{"@type": "NewsArticle", "audio": {"name": "AudioObject"}}</script>
        </head></html>
      HTML

      urls = described_class.candidate_urls(page_url: 'https://example.com/news/', parsed_body: doc).map(&:to_s)

      expect(urls.first(2)).to eq(%w[https://example.com/news.xml https://example.com/podcast.xml])
    end

    it 'ranks audio-hinted alternates last, in document order, on a page without podcast signals' do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <title>Example Daily: local news</title>
          <link rel="alternate" type="application/rss+xml" title="Tide Talk podcast" href="https://feeds.example.net/tide-talk/rss">
          <link rel="alternate" type="application/rss+xml" title="Example Daily news" href="https://example.com/feed.xml">
          <link rel="alternate" type="application/rss+xml" title="Show" href="/feed/mp3/">
          <link rel="alternate" type="application/rss+xml" title="Comments" href="/comments.xml">
        </head></html>
      HTML

      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: doc).map(&:to_s)

      expect(urls.first(4)).to eq(%w[https://example.com/feed.xml https://example.com/comments.xml
                                     https://feeds.example.net/tide-talk/rss https://example.com/feed/mp3/])
    end

    {
      'its URL path' => ['https://example.com/episodes/42', ''],
      'its title' => ['https://example.com/', '<title>Example AUDIO Archive</title>'],
      'an og:type of music.*' => ['https://example.com/', '<meta property="og:type" content=" Music.Song">'],
      'an og:type of video.*' => ['https://example.com/', '<meta property="og:type" content="video.episode">'],
      'a Schema PodcastSeries' =>
        ['https://example.com/', '<script type="application/ld+json">{"@type": "PodcastSeries"}</script>'],
      'a nested Schema PodcastEpisode URL type' =>
        ['https://example.com/', '<script type="application/ld+json">{"@graph": [{"@type" : ' \
                                 '["WebPage", "https://schema.org/PodcastEpisode"]}]}</script>'],
      'a Schema AudioObject' =>
        ['https://example.com/', '<script type="application/ld+json">{"@type":"audioobject"}</script>']
    }.each do |signal, (page_url, head)|
      it "prefers the audio-hinted alternate on a podcast page shown by #{signal}" do
        doc = Nokogiri::HTML(<<~HTML)
          <html><head>#{head}
            <link rel="alternate" type="application/rss+xml" title="News" href="/news.xml">
            <link rel="alternate" type="application/rss+xml" title="Show" href="/feed/mp3/">
          </head></html>
        HTML

        urls = described_class.candidate_urls(page_url:, parsed_body: doc).map(&:to_s)

        expect(urls.first(2)).to eq(%w[https://example.com/feed/mp3/ https://example.com/news.xml])
      end
    end

    it 'ignores podcast words outside the page path and non-media og:types', :aggregate_failures do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <meta property="og:type" content="article.music">
          <script type="text/plain">{"@type": "PodcastSeries"}</script>
          <link rel="alternate" type="application/rss+xml" title="News" href="/news.xml">
          <link rel="alternate" type="application/rss+xml" title="Podcast" href="/podcast.xml">
        </head></html>
      HTML

      urls = described_class.candidate_urls(page_url: 'https://example.com/news?type=podcast', parsed_body: doc)

      expect(urls.first.to_s).to eq('https://example.com/news.xml')
    end

    it 'matches podcast page hints word-ish and case-insensitively', :aggregate_failures do
      hinted = ['Podcasts', '/episode-12/', 'Example AUDIO']
      unhinted = ['Audiobooks', 'Podcasting tips', '/mp3/', 'News']

      expect(hinted.grep(described_class::PODCAST_PAGE_HINT)).to eq(hinted)
      expect(unhinted.grep(described_class::PODCAST_PAGE_HINT)).to be_empty
    end

    it 'matches audio hints word-ish and case-insensitively', :aggregate_failures do
      hinted = ['Podcast Feed', 'EPISODES', 'Audio', '/feed/opus/', '/podcast09/x.xml', '/aac.xml', '/podcasts/']
      unhinted = ['Audiobooks', 'Podcasting tips', '/feed/mp3x', 'aacounty', 'News feed']

      expect(hinted.grep(described_class::AUDIO_HINT)).to eq(hinted)
      expect(unhinted.grep(described_class::AUDIO_HINT)).to be_empty
    end

    it 'reads head alternates from any HTML document subclass' do
      doc = Nokogiri::HTML5('<head><link rel="alternate" type="application/rss+xml" href="/h5.xml"></head>')

      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: doc)

      expect(urls.first.to_s).to eq('https://example.com/h5.xml')
    end

    it 'keeps document order when no alternate hints audio' do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <link rel="alternate" type="application/rss+xml" title="News" href="/news.xml">
          <link rel="alternate" type="application/atom+xml" title="Comments" href="/comments.xml">
        </head></html>
      HTML

      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: doc).map(&:to_s)

      expect(urls.first(2)).to eq(%w[https://example.com/news.xml https://example.com/comments.xml])
    end

    it 'falls back to string HTML alternate scanning when no document is given' do
      html = '<link rel="alternate" type="application/atom+xml" href="/atom.xml">'
      urls = described_class.candidate_urls(page_url: 'https://example.com/', html:)

      expect(urls.first.to_s).to eq('https://example.com/atom.xml')
    end

    it 'orders alternates, directory guesses, catalog paths, then extra paths', :aggregate_failures do
      html = '<link rel="alternate" type="application/rss+xml" href="/feed">'

      urls = described_class.candidate_urls(
        page_url: 'https://example.com/news/index.html', html:, extra_paths: ['/extra', '/feed']
      )

      expect(urls.map(&:to_s)).to eq(%w[
                                       https://example.com/feed
                                       https://example.com/news/feed
                                       https://example.com/news/rss.xml
                                       https://example.com/news/atom.xml
                                       https://example.com/feed.xml
                                       https://example.com/rss
                                       https://example.com/rss.xml
                                       https://example.com/atom.xml
                                       https://example.com/index.xml
                                       https://example.com/news/rss
                                       https://example.com/blog/feed
                                       https://example.com/blog/rss.xml
                                       https://example.com/extra
                                     ])
    end

    it 'works without html or a parsed body and ignores a non-document parsed body', :aggregate_failures do
      expect(described_class.candidate_urls(page_url: 'https://example.com/')).to include(
        Html2rss::Url.from_absolute('https://example.com/feed')
      )

      html = '<link rel="alternate" type="application/atom+xml" href="/atom-alt.xml">'
      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: 'not a document', html:)

      expect(urls.first.to_s).to eq('https://example.com/atom-alt.xml')
    end

    it 'drops hrefs and extra paths that cannot be resolved to a URL', :aggregate_failures do
      html = '<link rel="alternate" type="application/rss+xml" href="http://exa mple.com/x">'

      urls = nil
      expect do
        urls = described_class.candidate_urls(
          page_url: 'https://example.com/', html:, extra_paths: ['ht tp://x', '/kept']
        )
      end.not_to raise_error
      expect(urls).to all(be_a(Html2rss::Url))
      expect(urls.map(&:to_s)).to include('https://example.com/kept')
      expect(urls.map(&:to_s)).not_to include(a_string_including('exa mple'), a_string_including('ht tp'))
    end

    it 'falls back to string HTML alternates when the parsed document has none' do
      doc = Nokogiri::HTML('<html><head></head><body>no feeds</body></html>')
      html = '<link rel="alternate" type="application/rss+xml" href="/from-html.xml">'

      urls = described_class.candidate_urls(page_url: 'https://example.com/', parsed_body: doc, html:)

      expect(urls.first.to_s).to eq('https://example.com/from-html.xml')
    end
  end

  describe '.feedish?' do
    it 'accepts RSS content types' do
      expect(described_class.feedish?(feed_response(body: '<rss', content_type: 'application/rss+xml'))).to be true
    end

    it 'accepts body sniff when content type is plain' do
      expect(
        described_class.feedish?(
          feed_response(body: '<?xml version="1.0"?><rss version="2.0">', content_type: 'text/plain')
        )
      ).to be true
    end

    it 'rejects non-success status' do
      expect(
        described_class.feedish?(feed_response(body: '<rss', content_type: 'application/rss+xml', status: 404))
      ).to be false
    end

    it 'accepts only 2xx statuses, and nil when a body is present', :aggregate_failures do
      { 199 => false, 200 => true, 299 => true, 300 => false }.each do |status, expected|
        response = feed_response(body: '<rss', content_type: 'application/rss+xml', status:)
        expect(described_class.feedish?(response)).to be(expected), "status #{status}"
      end
      expect(described_class.feedish?(feed_response(body: '<rss', content_type: 'application/rss+xml', status: nil)))
        .to be true
    end

    it 'rejects a missing response and a non-feed body', :aggregate_failures do
      expect(described_class.feedish?(nil)).to be false
      expect(described_class.feedish?(feed_response(body: '<html>', content_type: 'text/html'))).to be false
    end
  end

  describe '.best_feed_url' do
    let(:page_url) { Html2rss::Url.from_absolute('https://example.com/news/') }
    let(:session) { instance_double(Html2rss::RequestSession) }
    let(:miss) { feed_response(body: 'not a feed', content_type: 'text/html') }
    let(:hit) do
      feed_response(body: '<rss version="2.0"></rss>', content_type: 'application/rss+xml',
                    url: 'https://example.com/news/atom.xml')
    end

    it 'stops at the first feedish candidate without probing further', :aggregate_failures do
      feed_response = Html2rss::RequestService::Response.new(
        body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>',
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/news/feed'),
        status: 200
      )

      allow(session).to receive(:follow_up).and_return(feed_response)

      selected = described_class.best_feed_url(
        page_url:,
        request_session: session,
        html: ''
      )

      expect(selected.to_s).to eq('https://example.com/news/feed')
      expect(session).to have_received(:follow_up).once
    end

    it 'skips probe errors and continues to the next candidate' do
      miss = Html2rss::RequestService::Response.new(
        body: 'not a feed',
        headers: { 'content-type' => 'text/html' },
        url: Html2rss::Url.from_absolute('https://example.com/news/rss.xml'),
        status: 200
      )
      hit = Html2rss::RequestService::Response.new(
        body: '<rss version="2.0"></rss>',
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/news/atom.xml'),
        status: 200
      )

      allow(session).to receive(:follow_up).and_invoke(
        ->(**) { raise Html2rss::RequestService::CrossOriginFollowUpDenied, 'denied' },
        ->(**) { miss },
        ->(**) { hit }
      )

      selected = described_class.best_feed_url(page_url:, request_session: session, html: '')

      # Candidates: /news/feed (error), /news/rss.xml (miss), /news/atom.xml (hit)
      expect(selected.to_s).to eq('https://example.com/news/atom.xml')
    end

    it 'caps candidate probes at max_probes when no feed is found', :aggregate_failures do
      miss = Html2rss::RequestService::Response.new(
        body: 'not a feed',
        headers: { 'content-type' => 'text/html' },
        url: Html2rss::Url.from_absolute('https://example.com/news/feed'),
        status: 200
      )
      allow(session).to receive(:follow_up).and_return(miss)

      selected = described_class.best_feed_url(
        page_url:,
        request_session: session,
        html: '',
        max_probes: 1
      )

      expect(selected).to be_nil
      expect(session).to have_received(:follow_up).once
    end

    it 'probes past misses when uncapped and finds a later feed', :aggregate_failures do
      allow(session).to receive(:follow_up).and_invoke(->(**) { miss }, ->(**) { miss }, ->(**) { hit })

      selected = described_class.best_feed_url(page_url:, request_session: session, html: '', max_probes: nil)

      expect(selected.to_s).to eq('https://example.com/news/atom.xml')
      expect(session).to have_received(:follow_up).exactly(3).times
    end

    it 'finds a feed within max_probes when it is the last allowed candidate' do
      allow(session).to receive(:follow_up).and_invoke(->(**) { miss }, ->(**) { hit })

      selected = described_class.best_feed_url(page_url:, request_session: session, html: '', max_probes: 2)

      expect(selected.to_s).to eq('https://example.com/news/atom.xml')
    end

    it 'probes candidates as same-origin auto-source follow-ups from the page origin', :aggregate_failures do
      allow(session).to receive(:follow_up).and_return(miss)

      described_class.best_feed_url(page_url:, request_session: session, html: '', max_probes: 1)

      expect(session).to have_received(:follow_up).with(
        url: having_attributes(to_s: 'https://example.com/news/feed'),
        relation: :auto_source,
        origin_url: having_attributes(host: 'example.com')
      )
    end

    it 'considers HTML string alternates before path guesses' do
      allow(session).to receive(:follow_up).and_return(hit)
      html = '<link rel="alternate" type="application/rss+xml" href="/alt.xml">'

      described_class.best_feed_url(page_url:, request_session: session, html:)

      expect(session).to have_received(:follow_up).with(
        url: having_attributes(to_s: 'https://example.com/alt.xml'), relation: :auto_source,
        origin_url: having_attributes(host: 'example.com')
      )
    end

    it 'fetches parsed-document alternates first, as advertised feeds carrying the page proof' do
      allow(session).to receive(:follow_up).and_return(hit)
      doc = Nokogiri::HTML('<head><link rel="alternate" type="application/rss+xml" href="/doc.xml"></head>')

      described_class.best_feed_url(page_url:, request_session: session, parsed_body: doc)

      expect(session).to have_received(:follow_up).with(
        url: having_attributes(to_s: 'https://example.com/doc.xml'), relation: :advertised_feed,
        origin_url: page_url,
        advertisement: having_attributes(
          page_url:, feeds: { Html2rss::Url.from_absolute('https://example.com/doc.xml') => '' }
        )
      )
    end

    it 'fetches an advertised feed on another host as an advertised feed of the page' do
      allow(session).to receive(:follow_up).and_return(hit)
      doc = Nokogiri::HTML(
        '<head><link rel="alternate" type="application/rss+xml" href="https://feeds.example.net/show.xml"></head>'
      )

      described_class.best_feed_url(page_url:, request_session: session, parsed_body: doc, max_probes: 1)

      expect(session).to have_received(:follow_up).once.with(
        url: Html2rss::Url.from_absolute('https://feeds.example.net/show.xml'), relation: :advertised_feed,
        origin_url: page_url, advertisement: kind_of(Html2rss::RequestService::FeedAdvertisement)
      )
    end

    it 'fetches an advertised http feed on another host as https only', :aggregate_failures do
      allow(session).to receive(:follow_up).and_raise(Html2rss::RequestService::ConnectionFailed, 'refused')
      doc = Nokogiri::HTML(
        '<head><link rel="alternate" type="application/rss+xml" href="http://feeds.example.net/show.xml"></head>'
      )

      selected = described_class.best_feed_url(page_url:, request_session: session, parsed_body: doc, max_probes: 1)

      expect(selected).to be_nil
      expect(session).to have_received(:follow_up).once
      expect(session).to have_received(:follow_up).with(hash_including(url: having_attributes(scheme: 'https')))
    end

    it 'probes path guesses as same-origin auto-source follow-ups even when the page advertises feeds' do
      allow(session).to receive(:follow_up).and_invoke(->(**) { miss }, ->(**) { miss })
      doc = Nokogiri::HTML('<head><link rel="alternate" type="application/rss+xml" href="/doc.xml"></head>')

      described_class.best_feed_url(page_url:, request_session: session, parsed_body: doc, max_probes: 2)

      expect(session).to have_received(:follow_up).with(
        url: having_attributes(to_s: 'https://example.com/news/feed'), relation: :auto_source, origin_url: page_url
      )
    end

    it 'probes caller-supplied extra paths' do
      allow(session).to receive(:follow_up).and_return(miss)

      described_class.best_feed_url(page_url:, request_session: session, html: '', extra_paths: ['/news/custom-feed'])

      expect(session).to have_received(:follow_up).with(
        url: having_attributes(to_s: 'https://example.com/news/custom-feed'), relation: :auto_source,
        origin_url: having_attributes(host: 'example.com')
      )
    end

    it 'returns the validated response itself, not only its URL' do
      allow(session).to receive(:follow_up).and_return(hit)

      response = described_class.best_feed_response(page_url:, request_session: session, html: '')

      expect(response).to be(hit)
    end

    it 'returns nil and logs no selection when no candidate is a feed', :aggregate_failures do
      allow(session).to receive(:follow_up).and_return(miss)
      allow(Html2rss::Log).to receive(:info)

      expect(described_class.best_feed_response(page_url:, request_session: session, html: '')).to be_nil
      expect(Html2rss::Log).not_to have_received(:info)
    end

    it 'logs the candidate count before probing', :aggregate_failures do
      allow(session).to receive(:follow_up).and_return(miss)
      allow(Html2rss::Log).to receive(:debug)

      described_class.best_feed_response(page_url:, request_session: session, html: '', extra_paths: ['/x'])

      expect(Html2rss::Log).to have_received(:debug).with(
        'Syndication::Discovery: host=example.com candidate_count=13'
      )
    end

    it 'logs a debug line and continues when a probe is refused' do
      allow(session).to receive(:follow_up).and_invoke(
        ->(**) { raise Html2rss::RequestService::CrossOriginFollowUpDenied, 'denied' },
        ->(**) { hit }
      )
      allow(Html2rss::Log).to receive(:debug)

      described_class.best_feed_response(page_url:, request_session: session, html: '', max_probes: 2)

      expect(Html2rss::Log).to have_received(:debug).with(
        'Syndication::Discovery: probe skipped host=example.com ' \
        '(Html2rss::RequestService::CrossOriginFollowUpDenied)'
      )
    end

    it 'logs a structured selection event with the chosen feed URL' do
      allow(session).to receive(:follow_up).and_return(hit)
      allow(Html2rss::Log).to receive(:info)

      described_class.best_feed_response(page_url:, request_session: session, html: '')

      expect(Html2rss::Log).to have_received(:info).with(
        {
          event_name: 'syndication.discovery.selected',
          host: 'example.com',
          message: 'Syndication::Discovery: host=example.com selected_feed_url=https://example.com/news/atom.xml'
        }.to_json
      )
    end
  end
end

# rubocop:enable RSpec/ExampleLength
