# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

require 'spec_helper'

# One set of invariants run over every path a scrape can take (HTML auto-source, RSS, Atom, entry resolution),
# so a rule enforced in one path but bypassed in another fails here. Transport is stubbed per URL.
# rubocop:disable-next RSpec/DescribeClass -- integration invariant spec; lives under spec/integration/
RSpec.describe 'Pipeline path invariants' do
  let(:origin) { 'https://example.com' }
  let(:limit) { 2 }
  let(:status) { 200 }
  let(:fallback_reachable) { false }
  let(:html_headers) { { 'content-type' => 'text/html; charset=utf-8' } }
  let(:response_for) do
    lambda do |body, url, headers, code = 200|
      Html2rss::RequestService::Response.new(
        body:, url: Html2rss::Url.from_absolute(url), headers:, status: code
      )
    end
  end

  let(:listing_html) do
    articles = (1..5).map do |i|
      "<article><h2><a href='#{origin}/news/post-#{i}-about-something-long'>Post #{i} about something long enough" \
        "</a></h2><p>Summary text number #{i} that is reasonably long to look like an excerpt of it.</p></article>"
    end
    "<html><head><title>News</title></head><body><main>#{articles.join}</main></body></html>"
  end
  let(:rss_body) do
    items = (1..5).map do |i|
      "<item><title>Post #{i}</title><link>#{origin}/p/#{i}</link><guid>#{origin}/p/#{i}</guid>" \
        "<description><![CDATA[<![CDATA[Body #{i}]]>]]></description></item>"
    end
    %(<?xml version="1.0"?><rss version="2.0"><channel><title>Feed</title><link>#{origin}/</link>) +
      "<description>d</description>#{items.join}</channel></rss>"
  end
  let(:atom_body) do
    entries = (1..5).map do |i|
      "<entry><title>Post #{i}</title><id>#{origin}/p/#{i}</id><link href='#{origin}/p/#{i}'/>" \
        "<updated>2024-01-0#{i}T00:00:00Z</updated>" \
        "<content type='html'>&lt;![CDATA[Body #{i}]]&gt;</content></entry>"
    end
    %(<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Feed</title>) \
      "<id>#{origin}/</id><updated>2024-01-05T00:00:00Z</updated>#{entries.join}</feed>"
  end
  let(:home_html) do
    nav = %w[news blog articles latest posts].map { |path| "<a href='/#{path}/'>#{path}</a>" }.join
    <<~HTML
      <html><head><title>Home</title>
      <link rel="alternate" type="application/rss+xml" href="#{origin}/feed.xml">
      </head><body><header><nav>#{nav}</nav></header><main><h1>Welcome</h1></main></body></html>
    HTML
  end
  let(:empty_urlset) { '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>' }
  let(:xml_headers) { { 'content-type' => 'application/xml' } }

  let(:paths) do
    {
      'an HTML page (auto-source)' => {
        entry: "#{origin}/news/", strategies: %i[default auto], resolved: false,
        pages: { "#{origin}/news/" => [listing_html, html_headers] }
      },
      'an HTML page with an items selector' => {
        entry: "#{origin}/news/", strategies: %i[default auto], resolved: false,
        options: { items_selector: 'article h2 a' },
        pages: { "#{origin}/news/" => [listing_html, html_headers] }
      },
      'a direct RSS feed' => {
        entry: "#{origin}/feed.xml", strategies: %i[default auto], resolved: false,
        pages: { "#{origin}/feed.xml" => [rss_body, { 'content-type' => 'application/rss+xml' }] }
      },
      'a direct Atom feed' => {
        entry: "#{origin}/atom.xml", strategies: %i[default auto], resolved: false,
        pages: { "#{origin}/atom.xml" => [atom_body, { 'content-type' => 'application/atom+xml' }] }
      },
      'an HTML page resolved to its listing' => {
        entry: "#{origin}/", strategies: %i[auto], resolved: true,
        pages: { "#{origin}/" => [home_html, html_headers], "#{origin}/news/" => [listing_html, html_headers],
                 "#{origin}/feed.xml" => [empty_urlset, xml_headers] }
      }
    }
  end

  before do
    allow(Html2rss::Log).to receive(:info)
    allow(Html2rss::Log).to receive(:warn).and_return(true)
    allow(Html2rss::Log).to receive(:debug)
    allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
      ctx.budget.consume!
      raise Html2rss::RequestService::ConnectionFailed, 'no response' unless strategy == :default || fallback_reachable

      body, headers = page_set.fetch(ctx.url.to_s) { raise Html2rss::RequestService::ConnectionFailed, 'no response' }
      response_for.call(body, ctx.url.to_s, headers, ctx.url.to_s == path.fetch(:entry) ? status : 200)
    end
  end

  permanent_statuses = [404, 410]
  refused_statuses = [401, 403, 429]
  [
    ['an HTML page (auto-source)', :default], ['an HTML page (auto-source)', :auto],
    ['an HTML page with an items selector', :default], ['an HTML page with an items selector', :auto],
    ['a direct RSS feed', :default], ['a direct RSS feed', :auto],
    ['a direct Atom feed', :default], ['a direct Atom feed', :auto],
    ['an HTML page resolved to its listing', :auto]
  ].each do |path_name, strategy|
    context "with #{path_name} under strategy #{strategy}" do
      let(:path) { paths.fetch(path_name) }
      let(:page_set) { path.fetch(:pages) }
      let(:entry) { path.fetch(:entry) }
      let(:options) { path.fetch(:options, {}) }
      let(:result) { Html2rss.scrape(entry, strategy:, limit:, **options) }
      let(:wire) { Html2rss::Curation::Batch.scrape_wire(url: entry, strategy:, limit:, **options) }

      it 'honours the item limit', :aggregate_failures do
        expect(result.to_rss.items.size).to eq(limit)
        expect(wire.fetch(:items).size).to eq(limit)
      end

      it 'reports the effective scrape URL and flags an applied resolution', :aggregate_failures do
        expect(result.status.scrape_url).not_to be_nil
        expect(result.status.entry_resolution).to include(applied: true) if path.fetch(:resolved)
        expect(result.status.scrape_url).to eq("#{origin}/news/") if path.fetch(:resolved)
      end

      it 'does not leak CDATA markers into item text', :aggregate_failures do
        texts = result.to_rss.items.flat_map { [_1.description.to_s, _1.content_encoded.to_s] }
        expect(texts.join).to match(/Body|Summary/)
        expect(texts.join).not_to include('<![CDATA[', ']]>')
        expect(wire.fetch(:items).join).not_to include('<![CDATA[', ']]>')
      end

      it 'carries scrape_url and entry_resolution on the batch wire only when applied', :aggregate_failures do
        expect(wire).to include(scrape_url: result.status.scrape_url)
        expect(wire.key?(:entry_resolution)).to eq(path.fetch(:resolved))
      end

      permanent_statuses.each do |code|
        context "when the entry responds #{code}" do
          let(:status) { code }

          it 'raises DeterministicHttpStatus and returns no items' do
            expect { result.to_rss }.to raise_error(Html2rss::RequestService::DeterministicHttpStatus)
          end
        end
      end

      refused_statuses.each do |code|
        context "when the entry responds #{code}" do
          let(:status) { code }
          let(:fallback_reachable) { true }

          it 'raises BlockedSurfaceDetected with the status and returns no items', :aggregate_failures do
            expect { result.to_rss }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected) do |error|
              expect(error.diagnostics).to include(status: code)
            end
          end
        end
      end
    end
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
