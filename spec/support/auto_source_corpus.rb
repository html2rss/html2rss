# frozen_string_literal: true

require 'yaml'

##
# Labeled auto-source corpus under spec/fixtures/auto_source/corpus/.
#
# Each page (+.html+ or +.json+) has a +.yml+ sidecar listing its expected article URLs.
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

  # Per-page score: junk = admitted URLs not in the sidecar; real = admitted sidecar URLs.
  Row = Data.define(:page, :junk, :real, :expected, :sst_built) do
    # @return [Array<String, Integer>] table cells in column order
    def cells = [page, junk, real, expected, sst_built ? 'yes' : 'no']
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

    # @param rows [Array<Row>]
    # @return [Hash{Symbol => Integer}] summed junk, real, expected and pages with SST built
    def totals(rows)
      {
        junk: rows.sum(&:junk),
        real: rows.sum(&:real),
        expected: rows.sum(&:expected),
        sst_built: rows.count(&:sst_built)
      }
    end

    # @param rows [Array<Row>]
    # @return [String] fixed-width table with a totals line
    def table(rows)
      sum = totals(rows)
      cells = [%w[page junk real expected sst]]
      cells.concat(rows.map(&:cells))
      cells << ['TOTAL', sum[:junk], sum[:real], sum[:expected], "#{sum[:sst_built]}/#{rows.size}"]
      line = "%-#{cells.map { _1.first.size }.max}s  %5s  %5s  %8s  %s"
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
      expected = expected_urls(page)
      admitted, sst_calls = with_sst_count { admitted_urls(page) }
      real = (admitted & expected).size
      Row.new(page:, junk: admitted.size - real, real:, expected: expected.size, sst_built: sst_calls.positive?)
    end

    def with_sst_count
      Thread.current[SST_CALLS] = 0
      [yield, Thread.current[SST_CALLS]]
    ensure
      Thread.current[SST_CALLS] = nil
    end

    def admitted_urls(page)
      response = Html2rss::RequestService::Response.new(
        body: File.read(File.join(ROOT, page)),
        headers: { 'content-type' => CONTENT_TYPES.fetch(File.extname(page)) },
        url: Html2rss::Url.from_absolute(BASE_URL)
      )
      Html2rss::AutoSource.new(response).articles.map { _1.url.to_s }.uniq
    end

    def expected_urls(page)
      sidecar = File.join(ROOT, "#{File.basename(page, '.*')}.yml")
      YAML.load_file(sidecar).fetch('expected').map { Html2rss::Url.from_absolute(_1).to_s }
    end
  end
end
