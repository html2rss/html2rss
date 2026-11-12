# frozen_string_literal: true

require 'yaml'

##
# Labeled auto-source corpus under spec/fixtures/auto_source/corpus/.
#
# Each page (+.html+ or +.json+) has a +.yml+ sidecar listing its expected article URLs and,
# optionally, a +titles+ map (expected URL => exact expected title).
# {.run} feeds every page through {Html2rss::AutoSource} with a fixed base URL and no
# request session (no network; {.auto_source} accepts one to serve saved follow-up responses), then scores the admitted URLs against the sidecar.
# Shared by bin/auto-source-corpus (table + baseline recording) and the ratchet spec.
#
# Saved pages are UTF-8 by contract (the capture tool re-encodes them, so an in-page
# +<meta charset>+ is stale). {.auto_source} owns building the response and declares UTF-8.
module AutoSourceCorpus
  ROOT = File.expand_path('../fixtures/auto_source/corpus', __dir__)
  BASELINE_PATH = File.join(ROOT, 'baseline.yml')
  BASE_URL = 'https://example.com/news/'
  CONTENT_TYPES = { '.html' => 'text/html', '.json' => 'application/json' }.freeze
  FEED_CONTENT_TYPE = 'application/xml'
  SAVED_PAGE_CHARSET = 'utf-8'
  RECORD_COMMAND = 'mise exec -- make corpus-baseline'
  SST_CALLS = :auto_source_corpus_sst_calls

  # Per-page score: junk = admitted URLs not in the sidecar; real = admitted sidecar URLs;
  # title_misses = sidecar titles the admitted article does not carry verbatim (absent counts).
  Row = Data.define(:page, :junk, :real, :expected, :title_misses, :sst_built) do
    # @return [Array<String, Integer>] table cells in column order
    def cells = [page, junk, real, expected, title_misses, sst_built ? 'yes' : 'no']
  end

  ##
  # Counts SST::Normalizer.call while a corpus page runs, so the report shows whether a
  # heuristic tier was reached without adding hooks to lib/.
  module SstProbe
    def call(...)
      Thread.current[SST_CALLS] += 1 if Thread.current[SST_CALLS]
      super
    end
  end

  class << self
    # @return [Array<String>] corpus page names (basename with extension), sorted
    def pages
      Dir.children(ROOT).select { CONTENT_TYPES.key?(File.extname(_1)) }.sort
    end

    # @return [Array<Row>] one scored row per corpus page
    def run
      install_sst_probe
      pages.map { run_page(_1) }
    end

    # Runs one saved page file through {Html2rss::AutoSource} offline. Without a request session the
    # follow-up tiers (native feed, WordPress API, sitemap, oEmbed) are skipped; pass a
    # {SavedResponses} to serve them from saved files instead (still no network).
    #
    # @param path [String] saved page file (+.html+, or +.json+ for a JSON document)
    # @param url [String] absolute page URL
    # @param request_session [#follow_up, nil] session for follow-up fetches
    # @return [Html2rss::AutoSource] not yet extracted; call +articles+
    def auto_source(path:, url: BASE_URL, request_session: nil)
      Html2rss::AutoSource.new(response(path:, url:), request_session:)
    end

    # The one builder of a Response from a saved file, shared with {SavedResponses}: pages are read
    # and declared as UTF-8 so a stale in-page meta charset never decodes them; +.xml+ feeds are read
    # as bytes, since they carry their own encoding declaration.
    #
    # @param path [String] saved file (+.html+, +.json+ or +.xml+)
    # @param url [String] absolute URL the file stands for
    # @return [Html2rss::RequestService::Response]
    def response(path:, url:)
      feed = File.extname(path) == '.xml'
      Html2rss::RequestService::Response.new(
        body: feed ? File.binread(path) : File.read(path, encoding: Encoding::UTF_8),
        headers: { 'content-type' => content_type(path, feed) }, status: 200, url: Html2rss::Url.from_absolute(url)
      )
    end

    # @param rows [Array<Row>]
    # @return [Hash{Symbol => Integer}] summed junk, real, expected and pages with SST built
    def totals(rows)
      {
        junk: rows.sum(&:junk),
        real: rows.sum(&:real),
        expected: rows.sum(&:expected),
        title_misses: rows.sum(&:title_misses),
        sst_built: rows.count(&:sst_built)
      }
    end

    # @param rows [Array<Row>]
    # @return [String] fixed-width table with a totals line
    def table(rows)
      sum = totals(rows)
      cells = [%w[page junk real expected title_miss sst]]
      cells.concat(rows.map(&:cells))
      cells << ['TOTAL', *sum.values_at(:junk, :real, :expected, :title_misses), "#{sum[:sst_built]}/#{rows.size}"]
      line = "%-#{cells.map { _1.first.size }.max}s  %5s  %5s  %8s  %10s  %s"
      cells.map { format(line, *_1) }.join("\n")
    end

    # @return [Hash{String => Hash{String => Object}}] recorded rows keyed by page
    def baseline
      YAML.load_file(BASELINE_PATH)
    end

    # @param rows [Array<Row>]
    # @return [void]
    def write_baseline(rows)
      recorded = rows.to_h { [_1.page, _1.to_h.except(:page).transform_keys(&:to_s)] }
      header = "# Auto-source corpus ratchet baseline. Re-record only via `#{RECORD_COMMAND}`.\n"
      File.write(BASELINE_PATH, header + YAML.dump(recorded))
    end

    private

    def content_type(path, feed)
      return FEED_CONTENT_TYPE if feed

      "#{CONTENT_TYPES.fetch(File.extname(path), 'text/html')}; charset=#{SAVED_PAGE_CHARSET}"
    end

    def install_sst_probe
      normalizer = Html2rss::SST::Normalizer.singleton_class
      normalizer.prepend(SstProbe) unless normalizer.include?(SstProbe)
    end

    def run_page(page)
      sidecar = YAML.load_file(File.join(ROOT, "#{File.basename(page, '.*')}.yml"))
      articles, sst_calls = with_sst_count { page_articles(page) }
      score(page, sidecar, articles, sst_calls.positive?)
    end

    def score(page, sidecar, articles, sst_built)
      expected = sidecar.fetch('expected').map { normalize(_1) }
      admitted = articles.map { _1.url.to_s }.uniq
      real = (admitted & expected).size
      Row.new(page:, junk: admitted.size - real, real:, expected: expected.size, sst_built:,
              title_misses: title_misses(articles, sidecar.fetch('titles', {})))
    end

    def title_misses(articles, expected_titles)
      titles = articles.to_h { [_1.url.to_s, _1.title] }
      expected_titles.count { |url, title| titles[normalize(url)] != title }
    end

    def normalize(url) = Html2rss::Url.from_absolute(url).to_s

    def with_sst_count
      Thread.current[SST_CALLS] = 0
      [yield, Thread.current[SST_CALLS]]
    ensure
      Thread.current[SST_CALLS] = nil
    end

    def page_articles(page)
      auto_source(path: File.join(ROOT, page)).articles
    end
  end
end
