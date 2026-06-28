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

        # Regexp to match content-related tokens.
        CONTENT_REGEXP = begin
          words = LinkHeuristics::PathClassifier::SEGMENT_SETS.fetch(:content)
          /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
        end.freeze

        # Regexp to match junk/utility-related tokens.
        JUNK_REGEXP = begin
          words = LinkHeuristics::PathClassifier::SEGMENT_SETS.fetch(:utility)
          /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
        end.freeze

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
          @anchor_selector = AnchorSelector.new(url)
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
            next if hard_junk_entry?(container, selected_anchor, destination_facts)

            quality = quality_score(container, selected_anchor, destination_facts)
            junk = junk_score(container, selected_anchor, destination_facts)

            Entry.new(
              container:,
              selected_anchor:,
              destination_facts:,
              quality_score: quality,
              junk_score: junk,
              final_score: quality - junk,
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
          HtmlExtractor::SemanticContainers.call(parsed_body)
        end

        private

        def document_position(container)
          (@document_positions ||= candidate_containers.each_with_index.to_h).fetch(container)
        end

        def quality_score(container, selected_anchor, destination_facts) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          words = word_count(title)
          container_text = visible_text(container)
          score = 0

          score += 40 if words >= 3
          score += 15 if words >= 7
          score += 20 if destination_facts&.url&.path.to_s.length > 6
          score += 15 if destination_facts&.content_path
          score += 15 if publish_marker?(container)
          score += 10 if descriptive_context?(container_text, title)
          score += 10 if article_container?(container)
          score += 10 if content_tokens?(container_tokens(container))
          score
        end

        def junk_score(container, selected_anchor, destination_facts) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          utility_text = @link_heuristics.utility_prefix_text?(title)
          recommended_text = @link_heuristics.recommended_text?(title)
          content_signal = destination_facts&.content_path
          no_content_signal = !content_signal
          non_content_utility_path =
            destination_facts&.utility_path &&
            no_content_signal &&
            !destination_facts&.strong_post_suffix
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          weak_container = !publish_signal && !descriptive_signal
          score = 0

          score += 25 if non_content_utility_path
          score += 15 if utility_text && word_count(title) <= 6
          score += 10 if destination_facts&.shallow
          score += 10 if weak_container
          score += 10 if recommended_text && no_content_signal
          score += 5 if destination_facts&.high_confidence_junk_path
          score += 15 if junk_tokens?(container_tokens(container))
          score
        end

        # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def hard_junk_entry?(container, selected_anchor, destination_facts)
          title = entry_title(container, selected_anchor)
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          content_signal = destination_facts&.content_path
          weak_article_candidate = article_signal_count(
            container,
            publish_signal:,
            descriptive_signal:,
            content_signal:
          ) < 2

          destination_facts&.high_confidence_junk_path ||
            (selected_anchor &&
              @link_heuristics.recommended_text?(title) &&
              destination_facts&.shallow &&
              weak_article_candidate) ||
            (selected_anchor && @link_heuristics.utility_prefix_text?(title) &&
              destination_facts&.high_confidence_utility_destination &&
              weak_article_candidate)
        end
        # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        ##
        # @param container [Nokogiri::XML::Node]
        # @return [Boolean]
        def publish_marker?(container)
          (@publish_markers ||= {}.compare_by_identity)[container] ||=
            !!container.at_css('time, [datetime], [itemprop="datePublished"], [itemprop="dateModified"]')
        end

        ##
        # @param container [Nokogiri::XML::Node]
        # @param publish_signal [Boolean]
        # @param descriptive_signal [Boolean]
        # @param content_signal [Boolean]
        # @return [Integer]
        def article_signal_count(container, publish_signal:, descriptive_signal:, content_signal:)
          [article_container?(container), publish_signal, descriptive_signal, content_signal].count(&:itself)
        end

        ##
        # @param container [Nokogiri::XML::Node]
        # @return [Boolean]
        def article_container?(container) = container.name == 'article'

        def descriptive_context?(container_text, title)
          snippet = container_text.to_s.sub(/\A#{Regexp.escape(title.to_s)}/i, '')
          # Only check for existence of enough words if snippet is long enough to have them
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

        def content_tokens?(tokens)
          tokens.match?(CONTENT_REGEXP)
        end

        def junk_tokens?(tokens)
          tokens.match?(JUNK_REGEXP)
        end

        def stable_rank(entries)
          entries.sort_by { |entry| [-entry.final_score, entry.position] }
        end
      end
    end
  end
end
