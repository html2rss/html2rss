# frozen_string_literal: true

require 'json'
require_relative 'auto_source_corpus'

##
# Dev tooling behind bin/compare-revisions: runs saved pages through {Html2rss::AutoSource}
# offline (via {AutoSourceCorpus.auto_source}, the single runner) and diffs two revisions' results.
#
# A pages directory holds saved page files plus a +manifest.tsv+ of tab-separated
# +file+ and +url+ lines (blank lines and +#+ comments ignored); the url is the page's base URL.
module RevisionComparison
  MANIFEST = 'manifest.tsv'

  # One manifest entry.
  Page = Data.define(:file, :url)

  ##
  # One page run on one revision: admitted items (URL => title), Cleanup drop tallies,
  # wall time, and the error message when the run raised.
  Run = Data.define(:items, :drops, :wall_ms, :error) do
    # @param hash [Hash{String => Object}] a parsed {#to_h} document
    # @return [Run]
    def self.from_h(hash) = new(**hash.slice(*members.map(&:to_s)).transform_keys(&:to_sym))
  end

  ##
  # Base-versus-head comparison for one page.
  Diff = Data.define(:page, :base, :head) do
    # @return [Hash{String => String}] items only head admits
    def gained = head.items.except(*base.items.keys)

    # @return [Hash{String => String}] items only base admits
    def lost = base.items.except(*head.items.keys)

    # @return [Array<Array(String, String, String)>] +[url, base title, head title]+ for shared items
    def title_changes
      head.items.slice(*base.items.keys).filter_map do |url, to|
        from = base.items.fetch(url)
        [url, from, to] unless from == to
      end
    end

    # @return [Hash{String => Array(Integer, Integer)}] reason => +[base, head]+ Cleanup drop tally
    def drop_tallies
      reasons = (base.drops.keys | head.drops.keys).sort
      reasons.to_h { [_1, [base.drops.fetch(_1, 0), head.drops.fetch(_1, 0)]] }
    end
  end

  class << self
    # @param text [String] manifest contents
    # @return [Array<Page>]
    def parse_manifest(text)
      text.each_line(chomp: true).filter_map do |line|
        next if line.strip.empty? || line.start_with?('#')

        file, url = line.split("\t", 2)
        raise ArgumentError, "manifest line needs '<file>\\t<url>': #{line.inspect}" unless file && url

        Page.new(file: file.strip, url: url.strip)
      end
    end

    # @param dir [String] pages directory
    # @param limit [Integer, nil] keep only the first +limit+ pages
    # @return [Array<Page>]
    def load_pages(dir, limit: nil)
      pages = parse_manifest(File.read(File.join(dir, MANIFEST)))
      limit ? pages.first(limit) : pages
    end

    # Runs every page on the revision whose +lib/+ is loaded. Called inside the per-revision worker.
    #
    # @param pages [Array<Page>]
    # @param dir [String] pages directory
    # @return [Array<Run>] one per page, in order
    def measure(pages, dir) = pages.map { measure_page(_1, dir) }

    # @param pages [Array<Page>]
    # @param base_runs [Array<Run>]
    # @param head_runs [Array<Run>]
    # @return [Array<Diff>]
    def diffs(pages, base_runs, head_runs)
      pages.zip(base_runs, head_runs).map { |page, base, head| Diff.new(page:, base:, head:) }
    end

    # @param diffs [Array<Diff>]
    # @param labels [Array<String>] +[base, head]+ revision labels
    # @return [String] per-page report plus a totals line
    def report(diffs, labels)
      [
        "compare-revisions #{labels.first} -> #{labels.last} (#{diffs.size} pages)",
        *diffs.map { page_block(_1) },
        totals_line(diffs)
      ].join("\n")
    end

    private

    def measure_page(page, dir)
      started = now
      items, drops = extract(page, dir)
      Run.new(items:, drops:, wall_ms: ((now - started) * 1000).round(2), error: nil)
    rescue StandardError => error
      Run.new(items: {}, drops: {}, wall_ms: 0.0, error: "#{error.class}: #{error.message}")
    end

    def extract(page, dir)
      content_type = AutoSourceCorpus::CONTENT_TYPES.fetch(File.extname(page.file), 'text/html')
      source = AutoSourceCorpus.auto_source(body: File.read(File.join(dir, page.file)), content_type:, url: page.url)
      [source.articles.to_h { [_1.url.to_s, _1.title.to_s] }, source.admission_drops]
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def page_block(diff) = ["#{diff.page.file}  #{diff.page.url}", *detail_lines(diff)].join("\n")

    def detail_lines(diff)
      [
        "  items  #{diff.base.items.size} -> #{diff.head.items.size}",
        *error_lines(diff), *change_lines(diff), *drop_lines(diff),
        "  wall   #{wall([diff.base])} -> #{wall([diff.head])}"
      ]
    end

    def error_lines(diff)
      { 'base' => diff.base, 'head' => diff.head }.filter_map do |side, run|
        "  error  #{side}: #{run.error}" if run.error
      end
    end

    def change_lines(diff)
      [*item_lines('lost', diff.lost), *item_lines('gained', diff.gained), *title_lines(diff)]
    end

    def item_lines(label, items) = items.map { |url, title| "  #{label.ljust(6)} #{url}  #{title.inspect}" }

    def title_lines(diff)
      diff.title_changes.flat_map do |url, from, to|
        ["  title  #{url}", "           - #{from.inspect}", "           + #{to.inspect}"]
      end
    end

    def drop_lines(diff) = diff.drop_tallies.map { |reason, (from, to)| "  drops  #{reason}: #{from} -> #{to}" }

    def totals_line(diffs)
      counts = ["lost #{diffs.sum { _1.lost.size }}", "gained #{diffs.sum { _1.gained.size }}",
                "retitled #{diffs.sum { _1.title_changes.size }}"]
      ['TOTAL', items_total(diffs), *counts, wall_total(diffs)].join('  ')
    end

    def items_total(diffs) = "items #{diffs.sum { _1.base.items.size }} -> #{diffs.sum { _1.head.items.size }}"

    def wall_total(diffs) = "wall #{wall(diffs.map(&:base))} -> #{wall(diffs.map(&:head))}"

    def wall(runs) = "#{runs.sum(&:wall_ms).round(2)}ms"
  end
end
