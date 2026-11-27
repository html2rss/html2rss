# frozen_string_literal: true

require 'yaml'

##
# Labeled auto-source corpus under spec/fixtures/auto_source/corpus/.
#
# Each page (+.html+ or +.json+) has a +.yml+ sidecar listing its expected article URLs and,
# optionally, a +titles+ map (expected URL => exact expected title), a +media+ list (audio or
# video URLs the page may admit beside its articles: scored neither real nor junk), an +enclosures+
# map (expected URL => a hash of the RSS enclosure facts the item ships, any of +url+, +type+, +length+
# and +duration+, each present key asserted; or null for no enclosure), an +images+
# map (expected URL => item image URL), and a +responses+ directory (relative to the corpus root) of saved follow-up responses ({SavedResponses}).
# {.run} feeds every page through {Html2rss::AutoSource} with a fixed base URL, no network, and a
# request session only when the sidecar names saved responses, then scores the admitted URLs against the sidecar.
# Shared by bin/auto-source-corpus (table + baseline recording) and the ratchet spec.
#
# A saved page whose bytes are valid UTF-8 is UTF-8 (the capture tool re-encodes pages, so an in-page
# +<meta charset>+ may be stale). A page whose bytes are not is decoded by {Html2rss::RequestService::Response}
# from its own +<meta charset>+, as in production. {.response} owns building the response.
module AutoSourceCorpus # rubocop:disable Metrics/ModuleLength -- one cohesive corpus runner
  ROOT = File.expand_path('../fixtures/auto_source/corpus', __dir__)
  BASELINE_PATH = File.join(ROOT, 'baseline.yml')
  BASE_URL = 'https://example.com/news/'
  # The fixed run time of every saved page.
  NOW = Time.utc(2026, 11, 20, 12)
  CONTENT_TYPES = { '.html' => 'text/html', '.json' => 'application/json' }.freeze
  FEED_CONTENT_TYPE = 'application/xml'
  RECORD_COMMAND = 'mise exec -- make corpus-baseline'
  SST_CALLS = :auto_source_corpus_sst_calls
  # Summed per-page scores, in table column order.
  SCORES = %i[junk real expected title_misses enclosure_misses image_misses].freeze

  # Per-page score: junk = admitted URLs not in the sidecar (+media+ URLs excepted); real = admitted sidecar URLs;
  # title_misses = sidecar titles the admitted article does not carry verbatim (absent counts);
  # enclosure_misses / image_misses = sidecar enclosures / images the admitted article does not ship.
  Row = Data.define(:page, :junk, :real, :expected, :title_misses, :enclosure_misses, :image_misses, :sst_built) do
    # @return [Array<String, Integer>] table cells in column order
    def cells = [page, junk, real, expected, title_misses, enclosure_misses, image_misses, sst_built ? 'yes' : 'no']
  end

  ##
  # Counts Html::SST::Normalizer.call while a corpus page runs, so the report shows whether a
  # heuristic tier was reached without adding hooks to lib/.
  module SstProbe
    def call(...)
      Thread.current[SST_CALLS] += 1 if Thread.current[SST_CALLS]
      super
    end
  end

  # Stands in for the network when a run has no saved follow-up responses: every follow-up is unreachable, so
  # the follow-up tiers (native feed, WordPress API, sitemap, oEmbed) find nothing.
  module Offline
    def self.follow_up(url:, **)
      raise Html2rss::RequestService::ConnectionFailed, "offline: #{url}"
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

    # Runs one saved page file through the extraction kernel offline, driving its follow-up requests from
    # +request_session+; pass a {SavedResponses} to serve them from saved files (still no network).
    #
    # @param path [String] saved page file (+.html+, or +.json+ for a JSON document)
    # @param url [String] absolute page URL
    # @param request_session [#follow_up, nil] session for follow-up fetches; nil is offline
    # @return [Html2rss::Extraction::Outcome] +articles+ and +admission_drops+ of the run
    def extraction(path:, url: BASE_URL, request_session: nil)
      Html2rss::FeedPipeline.drive(
        response: response(path:, url:), options: Html2rss::AutoSource::DEFAULT_CONFIG,
        clock: Html2rss::AutoSource::Clock.new(now: NOW, time_zone: nil), session: request_session || Offline
      )
    end

    # The one builder of a Response from a saved file, shared with {SavedResponses}: a page whose bytes are
    # valid or near-valid UTF-8 ({PageBytes}) is declared UTF-8 so a stale in-page meta charset never decodes it;
    # any other page declares no charset, so the Response decodes it from its in-page meta charset (or scrubs
    # it when there is none).
    # +.xml+ feeds are read as bytes, since they carry their own encoding declaration.
    #
    # @param path [String] saved file (+.html+, +.json+ or +.xml+)
    # @param url [String] absolute URL the file stands for
    # @return [Html2rss::RequestService::Response]
    def response(path:, url:)
      feed = File.extname(path) == '.xml'
      body = File.binread(path)
      Html2rss::RequestService::Response.new(
        body:, headers: { 'content-type' => content_type(path, feed, body) }, status: 200,
        url: Html2rss::Url.from_absolute(url)
      )
    end

    # @param rows [Array<Row>]
    # @return [Hash{Symbol => Integer}] summed scores and pages with SST built
    def totals(rows) = SCORES.to_h { [_1, rows.sum(&_1)] }.merge(sst_built: rows.count(&:sst_built))

    # @param rows [Array<Row>]
    # @return [String] fixed-width table with a totals line
    def table(rows)
      sum = totals(rows)
      cells = [%w[page junk real expected title_miss encl_miss image_miss sst]]
      cells.concat(rows.map(&:cells))
      cells << ['TOTAL', *sum.values_at(*SCORES), "#{sum[:sst_built]}/#{rows.size}"]
      line = "%-#{cells.map { _1.first.size }.max}s  %5s  %5s  %8s  %10s  %9s  %10s  %s"
      cells.map { format(line, *_1) }.join("\n")
    end

    # @return [Hash{String => Hash{String => Object}}] recorded rows keyed by page
    def baseline = YAML.load_file(BASELINE_PATH)

    # @param rows [Array<Row>]
    # @return [void]
    def write_baseline(rows)
      recorded = rows.to_h { [_1.page, _1.to_h.except(:page).transform_keys(&:to_s)] }
      header = "# Auto-source corpus ratchet baseline. Re-record only via `#{RECORD_COMMAND}`.\n"
      File.write(BASELINE_PATH, header + YAML.dump(recorded))
    end

    private

    def content_type(path, feed, body)
      return FEED_CONTENT_TYPE if feed

      type = CONTENT_TYPES.fetch(File.extname(path), 'text/html')
      PageBytes.utf8?(body.force_encoding(Encoding::UTF_8)) ? "#{type}; charset=utf-8" : type
    end

    def install_sst_probe
      normalizer = Html2rss::Html::SST::Normalizer.singleton_class
      normalizer.prepend(SstProbe) unless normalizer.include?(SstProbe)
    end

    def run_page(page)
      sidecar = YAML.load_file(File.join(ROOT, "#{File.basename(page, '.*')}.yml"))
      articles, sst_calls = with_sst_count { page_articles(page, sidecar['responses']) }
      score(page, sidecar, articles, sst_calls.positive?)
    end

    def score(page, sidecar, articles, sst_built)
      expected = sidecar_urls(sidecar, 'expected')
      admitted = articles.map { _1.url.to_s }.uniq - sidecar_urls(sidecar, 'media')
      real = (admitted & expected).size
      Row.new(page:, junk: admitted.size - real, real:, expected: expected.size, sst_built:,
              **field_misses(sidecar, articles))
    end

    def field_misses(sidecar, articles)
      by_url = articles.to_h { [_1.url.to_s, _1] }
      { title_misses: misses(by_url, sidecar['titles']) { _1&.title },
        enclosure_misses: misses(by_url, sidecar['enclosures']) { |article, facts| enclosure_of(article, facts&.keys) },
        image_misses: misses(by_url, sidecar['images']) { _1&.image&.to_s } }
    end

    # Sidecar entries (expected URL => expected value) whose admitted article yields another value.
    def misses(by_url, expectations)
      (expectations || {}).count { |url, expected| yield(by_url[normalize(url)], expected) != expected }
    end

    # The asserted facts of the RSS enclosure the item ships ({Html2rss::FeedBuilder::ItemPresentation.rss_enclosure_for});
    # nil when it ships none.
    def enclosure_of(article, keys)
      enclosure = article && Html2rss::FeedBuilder::ItemPresentation.rss_enclosure_for(article)
      return unless enclosure

      { 'url' => enclosure.url.to_s, 'type' => enclosure.type, 'length' => enclosure.bytes_length,
        'duration' => enclosure.duration }.slice(*keys)
    end

    def normalize(url) = Html2rss::Url.from_absolute(url).to_s

    def sidecar_urls(sidecar, key) = sidecar.fetch(key, []).map { normalize(_1) }

    def with_sst_count
      Thread.current[SST_CALLS] = 0
      [yield, Thread.current[SST_CALLS]]
    ensure
      Thread.current[SST_CALLS] = nil
    end

    def page_articles(page, responses)
      extraction(path: File.join(ROOT, page), request_session: saved_responses(responses)).articles
    end

    # Loaded on first use: SavedResponses builds its responses through this module.
    def saved_responses(dir)
      return unless dir

      require_relative 'saved_responses'
      SavedResponses.new(File.join(ROOT, dir))
    end
  end
end

##
# Whether saved page bytes are UTF-8: valid, or near-valid, meaning at most +INVALID_SHARE+ of the non-ASCII
# bytes are invalid (a stray byte in UTF-8 text). A legacy page (GBK, Big5, windows-1251) has nearly all its
# non-ASCII bytes invalid as UTF-8; near-valid UTF-8 declared legacy by a stale meta would decode to mojibake.
module AutoSourceCorpus
  module PageBytes
    INVALID_SHARE = 0.05

    # @param bytes [String] page bytes
    # @return [Boolean]
    def self.utf8?(bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      text.valid_encoding? || bytes.bytesize - text.scrub('').bytesize <= bytes.b.count("\x80-\xFF".b) * INVALID_SHARE
    end
  end
end
