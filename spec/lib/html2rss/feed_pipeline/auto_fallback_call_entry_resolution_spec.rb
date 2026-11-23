# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

require 'spec_helper'

# The attempt lifecycle around the entry-resolution tournament: who spends which request slot, what the
# retry records, and when the resolved URL turns sticky. Transport is stubbed per [strategy, url].
RSpec.describe Html2rss::FeedPipeline::AutoFallback, '#call' do
  let(:origin) { 'https://example.com' }
  let(:html_headers) { { 'content-type' => 'text/html; charset=utf-8' } }
  let(:xml_headers) { { 'content-type' => 'application/xml' } }
  let(:nav) { %w[news blog articles latest posts].map { |path| "<a href='/#{path}/'>#{path}</a>" }.join }
  let(:home_html) do
    <<~HTML
      <html><head><title>Home</title>
      <link rel="alternate" type="application/rss+xml" href="#{origin}/feed.xml">
      <link rel="https://api.w.org/" href="#{origin}/wp-json/">
      <link rel="sitemap" type="application/xml" href="#{origin}/sitemap.xml">
      </head><body><header><nav>#{nav}</nav></header><main><h1>Welcome</h1></main></body></html>
    HTML
  end
  let(:sitemap_index) do
    locations = (1..3).map { "<sitemap><loc>#{origin}/sm#{_1}.xml</loc></sitemap>" }.join
    %(<?xml version="1.0"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{locations}</sitemapindex>)
  end
  let(:empty_urlset) do
    '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>'
  end
  let(:listing_html) do
    articles = (1..8).map do |i|
      "<article><h2><a href='#{origin}/news/post-#{i}-about-something-long'>Post #{i} about something long enough" \
        "</a></h2><p>Summary text number #{i} that is reasonably long to look like an excerpt of it.</p></article>"
    end
    "<html><head><title>News</title></head><body><main>#{articles.join}</main></body></html>"
  end
  let(:listing_meta) { { 'error_category' => 'none' } }
  let(:default_pages) do
    {
      "#{origin}/" => response_for(home_html, "#{origin}/", html_headers),
      "#{origin}/sitemap.xml" => response_for(sitemap_index, "#{origin}/sitemap.xml", xml_headers),
      "#{origin}/sm1.xml" => response_for(empty_urlset, "#{origin}/sm1.xml", xml_headers),
      "#{origin}/sm2.xml" => response_for(empty_urlset, "#{origin}/sm2.xml", xml_headers),
      "#{origin}/sm3.xml" => response_for(empty_urlset, "#{origin}/sm3.xml", xml_headers),
      "#{origin}/news/" => response_for(listing_html, "#{origin}/news/", html_headers, transport_meta: listing_meta)
    }
  end
  let(:pages) { { default: default_pages, botasaurus: {} } }
  let(:requests) { [] }
  let(:raw_config) { { channel: { url: "#{origin}/" }, strategy: :auto, auto_source: {} } }
  let(:pipeline) { Html2rss::FeedPipeline.new(raw_config) }
  let(:result) { pipeline.to_result }

  def response_for(body, url, headers, transport_meta: {})
    Html2rss::RequestService::Response.new(
      body:, url: Html2rss::Url.from_absolute(url), headers:, status: 200, transport_meta:
    )
  end

  before do
    allow(Html2rss::Log).to receive(:info)
    allow(Html2rss::Log).to receive(:warn).and_return(true) # as the real logger does
    allow(Html2rss::Log).to receive(:debug)
    allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
      ctx.budget.consume!
      requests << { strategy:, relation: ctx.relation, url: ctx.url.to_s }
      pages.fetch(strategy).fetch(ctx.url.to_s) { raise Html2rss::RequestService::ConnectionFailed, 'no response' }
    end
  end

  context 'when a weak home leaves only three request slots at the ceiling' do
    it 'extracts the listing instead of starving the retry', :aggregate_failures do
      expect(result.to_rss.items.size).to eq(8)
      expect(result.status).to have_attributes(
        selected_strategy: :default, scrape_url: "#{origin}/news/", entry_resolution: hash_including(applied: true)
      )
      expect(requests.size).to be <= Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING
      expect(Html2rss::Log).not_to have_received(:info).with(a_string_including('auto_fallback.zero_items'))
    end

    it 'fetches the winning listing once, as a probe', :aggregate_failures do
      result

      listing_requests = requests.select { _1[:url] == "#{origin}/news/" }
      expect(listing_requests).to eq([{ strategy: :default, relation: :entry_resolution, url: "#{origin}/news/" }])
    end

    it 'keeps the winner transport telemetry on the recorded attempt' do
      expect(result.status.strategy_attempts.last).to include(
        strategy: :default, items_count: 8, transport_meta: listing_meta
      )
    end
  end

  context 'when the winning listing redirects to its final URL' do
    let(:default_pages) do
      super().merge(
        "#{origin}/news/" => response_for(listing_html, "#{origin}/news-latest/", html_headers)
      )
    end

    it 'reports the final URL as the effective scrape URL', :aggregate_failures do
      expect(result.status).to have_attributes(entry_url: "#{origin}/", scrape_url: "#{origin}/news-latest/")
      expect(result.to_rss.items.size).to eq(8)
    end
  end

  context 'when the tournament must leave the next strategy its initial request' do
    let(:default_pages) { super().except("#{origin}/news/") }
    let(:pages) do
      { default: default_pages, botasaurus: { "#{origin}/" => response_for(listing_html, "#{origin}/", html_headers) } }
    end

    it 'lets the browser strategy fetch the entry page', :aggregate_failures do
      expect(result.status).to have_attributes(selected_strategy: :botasaurus)
      expect(result.to_rss.items.size).to eq(8)
      expect(requests.count { _1[:strategy] == :botasaurus }).to eq(1)
    end

    it 'records the tournament even though the fallback won', :aggregate_failures do
      expect(result.status.entry_resolution).to include(applied: false)
      expect(requests.count { _1[:relation] == :entry_resolution }).to be < 5
    end
  end

  context 'when the resolved page extracts nothing' do
    let(:raw_config) do
      { channel: { url: "#{origin}/" }, strategy: :auto, request: { max_requests: 6 },
        auto_source: { scraper: { native_feed: { enabled: false }, wordpress_api: { enabled: false },
                                  sitemap: { enabled: false } } } }
    end
    let(:pages) do
      { default: default_pages,
        botasaurus: { "#{origin}/" => response_for(listing_html, "#{origin}/", html_headers) } }
    end

    before do
      allow(pipeline).to receive(:extract).and_wrap_original do |original, **kwargs|
        extraction = original.call(**kwargs)
        next extraction unless kwargs[:response].url.to_s == "#{origin}/news/"

        extraction.with(articles: [])
      end
    end

    it 'keeps the diagnostic, the entry target and moves on', :aggregate_failures do
      expect(result.status).to have_attributes(
        selected_strategy: :botasaurus, scrape_url: "#{origin}/", entry_resolution: hash_including(applied: true)
      )
      expect(result.status.strategy_attempts.map { _1[:items_count] }).to eq([0, 0, 8])
      expect(Html2rss::Log).to have_received(:info).with(a_string_including('auto_fallback.zero_items'))
    end
  end

  context 'when the resolved page extraction fails' do
    let(:raw_config) do
      { channel: { url: "#{origin}/" }, strategy: :auto, request: { max_requests: 6 },
        auto_source: { scraper: { native_feed: { enabled: false }, wordpress_api: { enabled: false },
                                  sitemap: { enabled: false } } } }
    end
    let(:pages) do
      { default: default_pages,
        botasaurus: { "#{origin}/" => response_for(listing_html, "#{origin}/", html_headers) } }
    end
    let(:failure) { Html2rss::RequestService::ConnectionFailed.new('boom') }

    before do
      allow(pipeline).to receive(:extract).and_wrap_original do |original, **kwargs|
        raise failure if kwargs[:response].url.to_s == "#{origin}/news/"

        original.call(**kwargs)
      end
    end

    context 'with a request budget error' do
      let(:failure) { Html2rss::RequestService::RequestBudgetExceeded.new('spent') }

      it 'logs it, keeps the diagnostic and lets the next strategy run', :aggregate_failures do
        expect(result.status).to have_attributes(
          selected_strategy: :botasaurus, entry_resolution: hash_including(applied: true)
        )
        expect(Html2rss::Log).to have_received(:warn).with(
          a_string_including('"event_name":"feed_resolution.budget_exhausted"', '"host":"example.com"',
                             '"message":"FeedResolution: entry resolution skipped (request budget exhausted)"')
            .and(satisfy { |line| !line.include?('error_class') })
        )
        expect(Html2rss::Log).to have_received(:info).with(a_string_including('auto_fallback.zero_items'))
      end
    end

    context 'with another request error' do
      it 'logs it and lets the next strategy run', :aggregate_failures do
        expect(result.status).to have_attributes(selected_strategy: :botasaurus)
        expect(Html2rss::Log).to have_received(:info).with(a_string_including('auto_fallback.zero_items'))
        expect(Html2rss::Log).to have_received(:warn).with(
          a_string_including(
            '"event_name":"feed_resolution.retry_failed"', '"host":"example.com"',
            '"error_class":"Html2rss::RequestService::ConnectionFailed"',
            '"message":"FeedResolution: entry resolution retry failed (Html2rss::RequestService::ConnectionFailed)"'
          )
        )
      end
    end

    context 'with an error that aborts the chain' do
      let(:failure) { Html2rss::RequestService::InvalidUrl.new('bad') }

      it 'aborts before the next strategy', :aggregate_failures do
        expect { result }.to raise_error(Html2rss::RequestService::InvalidUrl)
        expect(requests.count { _1[:strategy] == :botasaurus }).to eq(0)
      end
    end

    context 'with a contract error' do
      let(:failure) { Html2rss::RequestService::Context::InvalidError.new('broken') }

      it 're-raises it' do
        expect { result }.to raise_error(Html2rss::RequestService::Context::InvalidError)
      end
    end
  end

  context 'when no strategy finds items' do
    let(:raw_config) do
      { channel: { url: "#{origin}/" }, strategy: :auto, request: { max_requests: 8 },
        auto_source: { scraper: { native_feed: { enabled: false }, wordpress_api: { enabled: false },
                                  sitemap: { enabled: false } } } }
    end
    let(:default_pages) { super().except("#{origin}/news/") }
    let(:pages) { { default: default_pages, botasaurus: { "#{origin}/" => default_pages.fetch("#{origin}/") } } }

    it 'runs the tournament on the first hop only', :aggregate_failures do
      allow(Html2rss::FeedResolution).to receive(:call).and_call_original

      expect { result }.to raise_error(Html2rss::NoFeedItemsExtracted)
      expect(Html2rss::FeedResolution).to have_received(:call).once
      expect(requests.count { _1[:strategy] == :botasaurus }).to eq(1)
    end
  end

  context 'when the resolved page is extracted through a session of its own' do
    let(:raw_config) do
      { channel: { url: "#{origin}/" }, strategy: :auto, request: { max_requests: 6 },
        auto_source: { scraper: { native_feed: { enabled: false }, wordpress_api: { enabled: false },
                                  sitemap: { enabled: false } } } }
    end
    let(:sessions) { [] }

    before do
      allow(pipeline).to receive(:request_session_for).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do |session|
          allow(session).to receive(:remember!).and_call_original
          sessions << [kwargs[:scrape_url], session]
        end
      end
    end

    it 'builds it for the resolved URL and marks the winner page as visited', :aggregate_failures do
      result

      scrape_url, session = sessions.last
      expect(sessions.size).to eq(2)
      expect(scrape_url).to eq("#{origin}/news/")
      expect(session).to have_received(:remember!).with(Html2rss::Url.from_absolute("#{origin}/news/"))
    end
  end

  context 'when the resolved page extraction spends its own follow-up requests' do
    let(:raw_config) do
      { channel: { url: "#{origin}/" }, strategy: :auto, request: { max_requests: 4 },
        auto_source: { scraper: { native_feed: { enabled: false }, wordpress_api: { enabled: false },
                                  sitemap: { enabled: false } } } }
    end
    let(:pages) do
      { default: default_pages,
        botasaurus: { "#{origin}/" => response_for(listing_html, "#{origin}/", html_headers) } }
    end

    before do
      allow(pipeline).to receive(:extract).and_wrap_original do |original, **kwargs|
        extraction = original.call(**kwargs)
        next extraction unless kwargs[:response].url.to_s == "#{origin}/news/"

        kwargs[:request_session].follow_up(url: "#{origin}/extra", relation: :auto_source, origin_url: origin)
      rescue Html2rss::RequestService::ConnectionFailed
        extraction.with(articles: [])
      end
    end

    # Residual: the retry shares the feed budget, so its scraper follow-ups can spend the slot that the
    # tournament left for the next strategy (AutoFallback#retry_resolved builds the retry session on the
    # shared resources). Pinned as behavior, not endorsed.
    it 'can leave the next strategy without its initial request' do
      expect { result }.to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
