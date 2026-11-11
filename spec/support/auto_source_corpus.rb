# frozen_string_literal: true

require 'yaml'

##
# Labeled auto-source corpus under spec/fixtures/auto_source/corpus/.
#
# Each page (+.html+ or +.json+) has a +.yml+ sidecar listing its expected article URLs and,
# optionally, a +titles+ map (expected URL => exact expected title).
# {.run} feeds every page through {Html2rss::AutoSource} with a fixed base URL and no
# request session (no network), then scores the admitted URLs against the sidecar.
# Shared by bin/auto-source-corpus (table + baseline recording) and the ratchet spec.
module AutoSourceCorpus
  ROOT = File.expand_path('../fixtures/auto_source/corpus', __dir__)
  BASELINE_PATH = File.join(ROOT, 'baseline.yml')
  BASE_URL = 'https://example.com/news/'
  CONTENT_TYPES = { '.html' => 'text/html', '.json' => 'application/json' }.freeze
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

    # Runs one page body through {Html2rss::AutoSource} offline (no request session).
    # Shared with the revision-comparison tool so there is a single runner.
    #
    # @param body [String] raw page body
    # @param content_type [String] response content type
    # @param url [String] absolute page URL
    # @return [Html2rss::AutoSource] not yet extracted; call +articles+
    def auto_source(body:, content_type:, url: BASE_URL)
      response = Html2rss::RequestService::Response.new(
        body:, headers: { 'content-type' => content_type }, url: Html2rss::Url.from_absolute(url)
      )
      Html2rss::AutoSource.new(response)
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

    def install_sst_probe
      normalizer = Html2rss::SST::Normalizer.singleton_class
      normalizer.prepend(SstProbe) unless normalizer.include?(SstProbe)
    end

    def run_page(page)
      sidecar = YAML.load_file(File.join(ROOT, "#{File.basename(page, '.*')}.yml"))
      expected = sidecar.fetch('expected').map { normalize(_1) }
      articles, sst_calls = with_sst_count { page_articles(page) }
      admitted = articles.map { _1.url.to_s }.uniq
      real = (admitted & expected).size
      Row.new(page:, junk: admitted.size - real, real:, expected: expected.size,
              title_misses: title_misses(articles, sidecar.fetch('titles', {})), sst_built: sst_calls.positive?)
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
      content_type = CONTENT_TYPES.fetch(File.extname(page))
      auto_source(body: File.read(File.join(ROOT, page)), content_type:).articles
    end
  end
end
