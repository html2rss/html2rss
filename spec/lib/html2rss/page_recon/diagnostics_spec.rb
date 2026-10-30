# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable-next RSpec/MultipleMemoizedHelpers -- response/probe fixtures share across contexts
RSpec.describe Html2rss::PageRecon::Diagnostics do
  let(:html) { File.read('spec/fixtures/local_feed_test.html') }
  let(:response_url) { Html2rss::Url.from_absolute('https://example.com/blog') }
  let(:response_status) { 200 }
  let(:response_body) { html }
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: response_body,
      url: response_url,
      headers: { 'content-type' => 'text/html' },
      status: response_status
    )
  end
  let(:probe_strategy) { :default }
  let(:probe) do
    Html2rss::PageRecon::Probe.new(
      session: instance_double(Html2rss::RequestSession),
      response:,
      result: Html2rss::PageRecon.call(response:, url: 'https://example.com/blog'),
      strategy: probe_strategy
    )
  end

  before do
    allow(Html2rss::PageRecon).to receive(:probe) { probe }
  end

  it 'reports strategy, scrapers, and SST segment stats', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    report = described_class.call(url: 'https://example.com/blog', strategy: :auto)
    result = report.to_wire_h

    expect(report).to be_a(described_class::Report)
    expect(result[:strategy]).to eq(:default)
    expect(result[:html_response]).to be(true)
    expect(result[:html_present]).to be(true)
    expect(result[:likely_js_shell]).to be(false)
    expect(result[:redirect_summary]).to include(
      requested_url: 'https://example.com/blog',
      final_url: 'https://example.com/blog',
      status: 200,
      scheme_downgrade: false
    )
    expect(result[:sst]).to include(:node_count, :segment_stats)
  end

  context 'when Content-Type is octet-stream but the body is HTML' do
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: response_body,
        url: response_url,
        headers: { 'content-type' => 'application/octet-stream' },
        status: response_status
      )
    end

    it 'still reports html_response and runs SST', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

      expect(result[:content_type]).to eq('application/octet-stream')
      expect(result[:html_response]).to be(true)
      expect(result[:sst]).to include(:node_count, :segment_stats)
    end
  end

  context 'when the fetch downgrades https to http' do
    let(:response_url) { Html2rss::Url.from_absolute('http://example.com/blog') }
    let(:response_status) { 301 }

    it 'surfaces final URL, status, and scheme_downgrade from the paid fetch', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

      expect(result[:requested_url]).to eq('https://example.com/blog')
      expect(result[:final_url]).to eq('http://example.com/blog')
      expect(result[:status]).to eq(301)
      expect(result[:scheme_downgrade]).to be(true)
    end
  end

  context 'when the document has a native RSS alternate' do
    let(:response_body) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
        </head>
        <body>
          <a href="/feed">Guessed</a>
        </body>
        </html>
      HTML
    end

    it 'maps FeedLink alternate feeds and does not guess /feed paths', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      report = described_class.call(url: 'https://example.com/blog', strategy: :auto)
      result = report.to_wire_h

      expect(report.alternate_feeds?).to be(true)
      expect(result[:alternate_feeds]).to eq(
        [{ href: 'https://example.com/feed.xml', mime_type: 'application/rss+xml' }]
      )
      expect(result[:alternate_feeds].map { |feed| feed[:href] }).not_to include('/feed')
    end
  end

  context 'when HTML is present but no articles match' do
    let(:response_body) do
      <<~HTML
        <!DOCTYPE html>
        <html><head><title>Shell</title></head>
        <body><div id="root">#{'x' * 9_000}</div></body></html>
      HTML
    end

    before do
      allow(Html2rss::AutoSource::Scraper).to receive(:classify_no_scraper_surface).and_return(:app_shell)
    end

    it 'flags likely_js_shell', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

      expect(result[:html_present]).to be(true)
      expect(result[:articles_count]).to eq(0)
      expect(result[:likely_js_shell]).to be(true)
    end
  end

  context 'when a blocked interstitial is detected' do
    let(:response_body) { '<html><body>Checking your browser before accessing</body></html>' }
    let(:blocked_recon) do
      Html2rss::PageRecon::Result.new(
        requested_url: 'https://example.com/blog',
        final_url: 'https://example.com/blog',
        status: 200,
        scheme_downgrade: false,
        alternate_feeds: [],
        surface_category: :blocked_surface,
        articles_count: 0,
        admission_drops: {},
        segment_stats: nil,
        html_response: true,
        content_type: 'text/html',
        blocked_surface: 'cloudflare',
        sst: nil
      )
    end
    let(:probe) do
      Html2rss::PageRecon::Probe.new(
        session: instance_double(Html2rss::RequestSession),
        response:,
        result: blocked_recon,
        strategy: probe_strategy
      )
    end

    it 'does not classify blocked pages as js shells', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

      expect(result[:surface_category]).to eq(:blocked_surface)
      expect(result[:likely_js_shell]).to be(false)
    end
  end

  describe '.call with deep: true' do
    it 'uses botasaurus when configured and strategy is auto', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::MCP::Runtime).to receive(:botasaurus_configured?).and_return(true)
      allow(Html2rss::PageRecon).to receive(:probe).and_return(probe)

      described_class.call(url: 'https://example.com/blog', strategy: :auto, deep: true)

      expect(Html2rss::PageRecon).to have_received(:probe).with(
        'https://example.com/blog', hash_including(strategy: :botasaurus)
      )
    end
  end

  it 'builds a request session via PageRecon.probe', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    allow(Html2rss::PageRecon).to receive(:probe).and_call_original
    session = instance_double(Html2rss::RequestSession, fetch_initial_response: response)
    allow(Html2rss::RequestSession).to receive(:build).and_return(session)

    result = Html2rss::PageRecon.probe('https://example.com/blog', strategy: :default)
    expect(result.response).to eq(response)
    expect(Html2rss::RequestSession).to have_received(:build)
  end

  it 'reports none_found when no scraper matches' do
    allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(
      Html2rss::AutoSource::Scraper::NoScraperFound.new(category: :unsupported_surface)
    )

    expect(described_class.scraper_info(Nokogiri::HTML::Document.parse(html)))
      .to eq(none_found: 'unsupported_surface')
  end

  it 'reports xhr_capture with query-stripped endpoints for botasaurus', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    captured_response = Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      captured_responses: [
        {
          'url' => 'https://api.example.com/v1/articles?token=secret',
          'body' => '[{"title":"Captured","url":"/a"}]'
        }
      ]
    )
    bot_probe = Html2rss::PageRecon::Probe.new(
      session: instance_double(Html2rss::RequestSession),
      response: captured_response,
      result: Html2rss::PageRecon.call(response: captured_response, url: 'https://example.com/blog'),
      strategy: :botasaurus
    )
    allow(Html2rss::PageRecon).to receive(:probe).and_return(bot_probe)

    result = described_class.call(url: 'https://example.com/blog', strategy: :botasaurus).to_wire_h

    expect(result[:xhr_capture]).to include(
      count: 1,
      candidate_articles: true,
      sample_endpoints: ['https://api.example.com/v1/articles']
    )
    expect(result[:xhr_capture][:sample_endpoints].first).not_to include('token=')
  end

  it 'omits xhr_capture when strategy is not botasaurus' do
    result = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

    expect(result).not_to have_key(:xhr_capture)
  end

  it 'returns error for non-HTML parsed bodies' do
    expect(described_class.scraper_info({})).to eq(error: 'Response is not HTML')
  end

  describe '.batch' do
    it 'returns Reports in input order with per-URL error isolation', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(described_class).to receive(:call).with(url: 'https://example.com/ok', strategy: :auto)
                                              .and_return(described_class::Report.new(data: { status: 200 }))
      allow(described_class).to receive(:call).with(url: 'https://example.com/fail', strategy: :auto)
                                              .and_raise(Html2rss::Error, 'Connection failed')

      reports = described_class.batch(urls: ['https://example.com/ok', 'https://example.com/fail'], concurrency: 2)

      expect(reports.size).to eq(2)
      expect(reports.first.to_wire_h[:status]).to eq(200)
      expect(reports.last.to_wire_h[:scraper_eligibility]).to include(error: 'Html2rss::Error - Connection failed')
    end

    it 'builds the full error report shape for a failed URL', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(described_class).to receive(:call).with(url: 'https://example.com/fail', strategy: :auto)
                                              .and_raise(Html2rss::Error, 'Connection failed')

      report = described_class.batch(urls: ['https://example.com/fail']).first

      expect(report).to be_a(described_class::Report)
      expect(report.to_wire_h).to eq(
        requested_url: 'https://example.com/fail',
        final_url: 'https://example.com/fail',
        status: nil,
        scheme_downgrade: false,
        alternate_feeds: [],
        surface_category: :unsupported_surface,
        articles_count: 0,
        html_response: false,
        content_type: nil,
        strategy: nil,
        scraper_eligibility: { error: 'Html2rss::Error - Connection failed' }
      )
    end

    it 'does not mask programmer errors as per-URL reports' do
      allow(described_class).to receive(:call).and_raise(NoMethodError)

      expect { described_class.batch(urls: ['https://example.com/a']) }.to raise_error(NoMethodError)
    end
  end

  describe 'wire payload assembly' do
    it 'merges recon facts with diagnostic fields', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      wire = described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h

      expect(wire).to include(
        requested_url: 'https://example.com/blog',
        strategy: :default,
        html_present: true,
        likely_js_shell: false,
        redirect_summary: { requested_url: 'https://example.com/blog', final_url: 'https://example.com/blog',
                            status: 200, scheme_downgrade: false }
      )
      expect(wire).to have_key(:scraper_eligibility)
    end

    it 'logs the js shell body size and surface category when flagged', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:debug)
      large = Html2rss::RequestService::Response.new(
        body: 'x' * 9_000, url: response_url, headers: { 'content-type' => 'text/html' }, status: 200
      )
      recon = Html2rss::PageRecon::Result.new(
        requested_url: 'https://example.com/blog', final_url: 'https://example.com/blog', status: 200,
        scheme_downgrade: false, alternate_feeds: [], surface_category: :high_entropy_surface,
        articles_count: 0, admission_drops: {}, segment_stats: nil, html_response: true,
        content_type: 'text/html', blocked_surface: nil, sst: nil
      )
      allow(Html2rss::PageRecon).to receive(:probe).and_return(
        Html2rss::PageRecon::Probe.new(
          session: instance_double(Html2rss::RequestSession), response: large, result: recon, strategy: :default
        )
      )

      described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(Html2rss::Log).to have_received(:debug).with(
        'Diagnostics js_shell: bytesize=9000 surface_category=high_entropy_surface'
      )
    end
  end

  describe 'likely_js_shell flag' do
    let(:recon_fields) do
      {
        requested_url: 'https://example.com/blog', final_url: 'https://example.com/blog', status: 200,
        scheme_downgrade: false, alternate_feeds: [], surface_category: :high_entropy_surface,
        articles_count: 0, admission_drops: {}, segment_stats: nil, html_response: true,
        content_type: 'text/html', blocked_surface: nil, sst: nil
      }
    end
    let(:response_body) { 'x' * 9_000 }
    let(:recon) { Html2rss::PageRecon::Result.new(**recon_fields) }
    let(:probe) do
      Html2rss::PageRecon::Probe.new(
        session: instance_double(Html2rss::RequestSession), response:, result: recon, strategy: probe_strategy
      )
    end
    let(:js_shell) do
      described_class.call(url: 'https://example.com/blog', strategy: :auto).to_wire_h[:likely_js_shell]
    end

    it 'flags a weak surface with a large body and no articles', :aggregate_failures do
      expect(js_shell).to be(true)
    end

    it 'treats the body size threshold as inclusive' do
      response_body.replace('x' * 8_192)

      expect(js_shell).to be(true)
    end

    it 'does not flag a body one byte below the threshold' do
      response_body.replace('x' * 8_191)

      expect(js_shell).to be(false)
    end

    it 'flags app_shell surfaces regardless of body size' do
      recon_fields[:surface_category] = :app_shell
      response_body.replace('x' * 10)

      expect(js_shell).to be(true)
    end

    it 'does not flag a non-weak surface with a large body' do
      recon_fields[:surface_category] = :listing

      expect(js_shell).to be(false)
    end

    it 'flags unsupported_surface as weak' do
      recon_fields[:surface_category] = :unsupported_surface

      expect(js_shell).to be(true)
    end

    it 'does not flag an empty body' do
      recon_fields[:surface_category] = :app_shell
      response_body.replace('')

      expect(js_shell).to be(false)
    end

    it 'does not flag a response that is not HTML' do
      recon_fields[:surface_category] = :app_shell
      recon_fields[:html_response] = false

      expect(js_shell).to be(false)
    end

    it 'does not flag pages that already yielded articles' do
      recon_fields[:surface_category] = :app_shell
      recon_fields[:articles_count] = 1

      expect(js_shell).to be(false)
    end

    it 'does not flag blocked interstitials by key' do
      recon_fields[:surface_category] = :app_shell
      recon_fields[:blocked_surface] = 'cloudflare'

      expect(js_shell).to be(false)
    end

    it 'does not flag blocked_surface categories' do
      recon_fields[:surface_category] = :blocked_surface

      expect(js_shell).to be(false)
    end
  end

  describe '.redacted_endpoint' do
    it 'keeps only scheme, host, and path', :aggregate_failures do
      entry = { 'url' => 'https://user:pass@api.example.com/v1/articles?token=secret#frag' }

      expect(described_class.redacted_endpoint(entry)).to eq('https://api.example.com/v1/articles')
    end

    it 'accepts symbol-keyed entries' do
      expect(described_class.redacted_endpoint({ url: 'https://api.example.com/feed?a=1' }))
        .to eq('https://api.example.com/feed')
    end

    it 'returns nil without a URL, scheme, or host', :aggregate_failures do
      expect(described_class.redacted_endpoint({})).to be_nil
      expect(described_class.redacted_endpoint({ 'url' => '/relative/path?x=1' })).to be_nil
      expect(described_class.redacted_endpoint({ 'url' => 'http://[bad' })).to be_nil
    end
  end

  describe Html2rss::PageRecon::Result do
    let(:fields) do
      {
        requested_url: 'https://example.com/blog', final_url: 'https://example.com/blog', status: 200,
        scheme_downgrade: false, alternate_feeds: [], surface_category: :listing, articles_count: 2,
        admission_drops: {}, segment_stats: nil, html_response: true, content_type: 'text/html',
        blocked_surface: nil, sst: nil
      }
    end

    it 'omits empty optional keys', :aggregate_failures do
      expect(described_class.new(**fields).to_h).to eq(
        requested_url: 'https://example.com/blog', final_url: 'https://example.com/blog', status: 200,
        scheme_downgrade: false, alternate_feeds: [], surface_category: :listing, articles_count: 2,
        html_response: true, content_type: 'text/html'
      )
    end

    it 'includes optional keys when present', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- full optional key set
      optional = fields.merge(
        admission_drops: { short: 1 }, segment_stats: { found: 1 }, blocked_surface: 'cloudflare',
        sst: { node_count: 3 }
      )

      expect(described_class.new(**optional).to_h).to include(
        admission_drops: { short: 1 }, segment_stats: { found: 1 }, blocked_surface: 'cloudflare',
        sst: { node_count: 3 }
      )
    end
  end

  describe Html2rss::PageRecon::Diagnostics::Report do
    it 'exposes alternate_feeds? and articles_count predicates', :aggregate_failures do
      report = described_class.new(data: { alternate_feeds: [{ href: 'https://example.com/feed.xml' }],
                                           articles_count: 3 })

      expect(report.alternate_feeds?).to be(true)
      expect(report.articles_count).to eq(3)
    end
  end
end
