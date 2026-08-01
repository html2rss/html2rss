# frozen_string_literal: true

require_relative 'semantic_html/anchor_selector'
require_relative 'semantic_html/deduplicator'

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
      class SemanticHtml # rubocop:disable Metrics/ClassLength
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
        # @option opts [Boolean] :fallback_anchorless whether to extract anchorless blocks
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
          @fallback_anchorless = opts.fetch(:fallback_anchorless, false)
          @link_heuristics = LinkHeuristics.new(url)
          @anchor_selector = AnchorSelector.new(link_heuristics: @link_heuristics)
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

        protected

        def candidate_containers
          @candidate_containers ||= collect_candidate_containers
        end

        def primary_anchor_for(container)
          @anchor_selector.primary_anchor_for(container)
        end

        # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def extractable_entries
          @extractable_entries ||= candidate_containers.filter_map do |container|
            selected_anchor = primary_anchor_for(container)

            next unless selected_anchor || @fallback_anchorless

            destination_facts = selected_anchor ? normalized_destination(selected_anchor) : nil
            next if selected_anchor && !destination_facts

            signals = container_signals(container, selected_anchor, destination_facts)
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
        # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        # rubocop:disable Metrics/MethodLength
        def ranked_entries
          @ranked_entries ||= begin
            deduplicator = Deduplicator.new(@url, @extractor)
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

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def container_signals(container, selected_anchor, destination_facts)
          title = entry_title(container, selected_anchor)
          tokens = container_tokens(container)

          LinkHeuristics::ContainerSignals.new(
            title_word_count: word_count(title),
            path_length: destination_facts&.url&.path.to_s.length,
            content_path: destination_facts&.content_path,
            publish_marker: publish_marker?(container),
            descriptive_context: descriptive_context?(visible_text(container), title),
            article_container: container.name == 'article',
            content_tokens: @link_heuristics.content_tokens?(tokens),
            junk_tokens: @link_heuristics.junk_tokens?(tokens),
            utility_prefix_title: @link_heuristics.utility_prefix_text?(title),
            recommended_title: @link_heuristics.recommended_text?(title),
            utility_path: destination_facts&.utility_path,
            strong_post_suffix: destination_facts&.strong_post_suffix,
            shallow: destination_facts&.shallow,
            high_confidence_junk_path: destination_facts&.high_confidence_junk_path,
            high_confidence_utility_destination: destination_facts&.high_confidence_utility_destination,
            selected_anchor_present: !selected_anchor.nil?
          )
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        ##
        # @param container [Nokogiri::XML::Node]
        # @return [Boolean]
        def publish_marker?(container)
          (@publish_markers ||= {}.compare_by_identity)[container] ||=
            !!container.at_css('time, [datetime], [itemprop="datePublished"], [itemprop="dateModified"]')
        end

        def descriptive_context?(container_text, title)
          snippet = container_text.to_s.sub(/\A#{Regexp.escape(title.to_s)}/i, '')
          snippet.length > 30 && word_count(snippet) >= 8
        end

        ##
        # @param container [Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node, nil]
        def heading_for(container)
          (@headings ||= {}.compare_by_identity)[container] ||= container.at_css(AnchorSelector::HEADING_SELECTOR)
        end

        def normalized_destination(anchor)
          (@normalized_destinations ||= {}.compare_by_identity)[anchor] ||= @link_heuristics.destination_facts(anchor)
        end

        def visible_text(node)
          return '' unless node

          (@visible_texts ||= {}.compare_by_identity)[node] ||= HtmlExtractor.extract_visible_text(node).to_s.strip
        end

        ##
        # @param container [Nokogiri::XML::Node]
        # @param selected_anchor [Nokogiri::XML::Node]
        # @return [String]
        def entry_title(container, selected_anchor) = visible_text(heading_for(container) || selected_anchor)

        ##
        # @param text [String, #to_s]
        # @return [Integer]
        def word_count(text)
          (@word_counts ||= {})[text] ||= begin
            count = 0
            text.to_s.scan(/\p{Alnum}+/) { count += 1 }
            count
          end
        end

        def container_tokens(container)
          (@container_tokens ||= {}.compare_by_identity)[container] ||= "#{container['class']} #{container['id']}"
        end

        def stable_rank(entries)
          entries.sort_by { |entry| [-entry.final_score, entry.position] }
        end
      end
    end
  end
end
