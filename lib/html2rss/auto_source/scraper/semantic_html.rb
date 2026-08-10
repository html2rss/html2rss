# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers by choosing one primary content link per
      # block before extraction.
      #
      # This scraper is intentionally container-first:
      # 1. collect candidate semantic containers once
      # 2. select the strongest content-like anchor within each container
      # 3. extract fields from the container while honoring that anchor choice
      #
      # The result is lower recall on weak-signal blocks, but much better link
      # quality on modern teaser cards that mix headlines, utility links, and
      # duplicate image overlays.
      class SemanticHtml
        include Enumerable

        # Container plus selected anchor, scoring metadata, and extracted article.
        Entry = Data.define(
          :container,
          :selected_anchor,
          :destination_facts,
          :quality_score,
          :junk_score,
          :final_score,
          :position,
          :article
        )

        ##
        # @return [Symbol] config key used to enable or configure this scraper
        def self.options_key = :semantic_html

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when at least one semantic container has an eligible anchor
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: 'https://example.com').extractable?
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base url
        # @param extractor [Class] extractor class used for article extraction
        # @param opts [Hash] scraper-specific options
        # @option opts [Boolean] :fallback_anchorless whether to keep containers without a primary anchor
        def initialize(parsed_body, url:, extractor: Html2rss::Html::ArticleExtractor, **opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
          @permit_unanchored = opts.fetch(:fallback_anchorless, false)
          @link_heuristics = LinkHeuristics.new(url)
        end

        attr_reader :parsed_body

        ##
        # Yields extracted article hashes for each semantic container that
        # survives anchor selection.
        #
        # Detection and extraction share the same memoized entry list so this
        # scraper does not rerun anchor ranking once a page has already been
        # accepted as extractable.
        #
        # @yieldparam article_hash [Hash] extracted article hash
        # @return [Enumerator<Hash>]
        def each
          return enum_for(:each) unless block_given?

          ranked_entries.each { yield _1.article }
        end

        ##
        # Reports whether the page contains at least one semantic container with
        # a selectable primary anchor.
        #
        # @return [Boolean] true when at least one candidate container yields a primary anchor
        def extractable?
          extractable_entries.any?
        end

        # @return [Array<Nokogiri::XML::Node>]
        def candidate_containers
          @candidate_containers ||= collect_candidate_containers
        end

        # @param container [Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node, nil]
        def primary_anchor_for(container)
          Discovery::SemanticAnchorCandidates.new(
            container,
            link_heuristics: @link_heuristics
          ).to_a.max_by(&:score)&.anchor
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def extractable_entries
          @extractable_entries ||= candidate_containers.filter_map do |container|
            selected_anchor = primary_anchor_for(container)

            next unless selected_anchor || @permit_unanchored

            destination_facts = selected_anchor ? normalized_destination(selected_anchor) : nil
            next if selected_anchor && !destination_facts
            # Cheap path-only reject before title/DOM hard-junk observations.
            next if destination_facts&.high_confidence_junk_path

            signals = @link_heuristics.assess_container(container, selected_anchor, destination_facts:)
            next if signals.hard_junk?

            Entry.new(
              container:,
              selected_anchor:,
              destination_facts:,
              quality_score: signals.quality_score,
              junk_score: signals.junk_score,
              final_score: signals.final_score,
              position: document_position(container),
              article: nil
            )
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        # rubocop:disable Metrics/MethodLength
        def ranked_entries
          @ranked_entries ||= begin
            deduplicator = EntryDeduplicator.new(@url, @extractor)
            entries = deduplicator.call(extractable_entries)
            entries = stable_rank(entries)

            entries.filter_map do |entry|
              article = deduplicator.article_for(entry)
              next unless article

              Entry.new(
                container: entry.container,
                selected_anchor: entry.selected_anchor,
                destination_facts: entry.destination_facts,
                quality_score: entry.quality_score,
                junk_score: entry.junk_score,
                final_score: entry.final_score,
                position: entry.position,
                article:
              )
            end
          end
        end
        # rubocop:enable Metrics/MethodLength

        def collect_candidate_containers
          Discovery::SemanticContainers.call(parsed_body)
        end

        private

        def document_position(container)
          (@document_positions ||= candidate_containers.each_with_index.to_h).fetch(container)
        end

        def normalized_destination(anchor)
          (@normalized_destinations ||= {}.compare_by_identity)[anchor] ||= @link_heuristics.destination_facts(anchor)
        end

        def stable_rank(entries)
          entries.sort_by { |entry| [-entry.final_score, entry.position] }
        end
      end
    end
  end
end
