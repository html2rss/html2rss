# frozen_string_literal: true

require_relative 'semantic_html/anchor_selector'

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
        # @param _opts [Hash] scraper-specific options
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **_opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
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

        def extractable_entries # rubocop:disable Metrics/MethodLength
          @extractable_entries ||= candidate_containers.filter_map do |container|
            selected_anchor = primary_anchor_for(container)

            next unless selected_anchor

            destination_facts = normalized_destination(selected_anchor)
            next unless destination_facts
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

        # rubocop:disable Metrics/MethodLength
        def ranked_entries
          @ranked_entries ||= begin
            entries = deduplicate_by_destination(extractable_entries)
            entries = stable_rank(entries)

            entries.filter_map do |entry|
              article = entry_article(entry)
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
          @document_positions ||= candidate_containers.each_with_index.to_h

          @document_positions.fetch(container)
        end

        def quality_score(container, selected_anchor, destination_facts) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          title = entry_title(container, selected_anchor)
          words = word_count(title)
          container_text = visible_text(container)
          score = 0

          score += 40 if words >= 3
          score += 15 if words >= 7
          score += 20 if destination_facts.url.path.to_s.length > 6
          score += 15 if destination_facts.content_path
          score += 15 if publish_marker?(container)
          score += 10 if descriptive_context?(container_text, title)
          score += 10 if article_container?(container)
          score
        end

        def junk_score(container, selected_anchor, destination_facts) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          utility_text = @link_heuristics.utility_prefix_text?(title)
          recommended_text = @link_heuristics.recommended_text?(title)
          non_content_utility_path =
            destination_facts.utility_path &&
            !destination_facts.content_path &&
            !destination_facts.strong_post_suffix
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          content_signal = destination_facts.content_path
          weak_container = !publish_signal && !descriptive_signal
          score = 0

          score += 25 if non_content_utility_path
          score += 15 if utility_text && word_count(title) <= 6
          score += 10 if destination_facts.shallow
          score += 10 if weak_container
          score += 10 if recommended_text && !content_signal
          score += 5 if destination_facts.high_confidence_junk_path
          score
        end

        def hard_junk_entry?(container, selected_anchor, destination_facts) # rubocop:disable Metrics/MethodLength
          title = entry_title(container, selected_anchor)
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          content_signal = destination_facts.content_path
          weak_article_candidate = article_signal_count(
            container,
            publish_signal:,
            descriptive_signal:,
            content_signal:
          ) < 2

          destination_facts.high_confidence_junk_path ||
            (@link_heuristics.recommended_text?(title) && destination_facts.shallow && weak_article_candidate) ||
            (@link_heuristics.utility_prefix_text?(title) &&
              destination_facts.high_confidence_utility_destination &&
              weak_article_candidate)
        end

        def publish_marker?(container)
          container.at_css('time, [datetime], [itemprop="datePublished"], [itemprop="dateModified"]')
        end

        def article_signal_count(container, publish_signal:, descriptive_signal:, content_signal:)
          [article_container?(container), publish_signal, descriptive_signal, content_signal].count(&:itself)
        end

        def article_container?(container)
          container.name == 'article'
        end

        def descriptive_context?(container_text, title)
          snippet = container_text.to_s.sub(/\A#{Regexp.escape(title.to_s)}/i, '')
          word_count(snippet) >= 8
        end

        def heading_for(container)
          container.at_css(AnchorSelector::HEADING_SELECTOR)
        end

        def normalized_destination(anchor)
          @link_heuristics.destination_facts(anchor)
        end

        def visible_text(node)
          return '' unless node

          HtmlExtractor.extract_visible_text(node).to_s.strip
        end

        def entry_title(container, selected_anchor)
          visible_text(heading_for(container) || selected_anchor)
        end

        def word_count(text)
          text.to_s.scan(/\p{Alnum}+/).size
        end

        def entry_article(entry)
          return entry.article if entry.article

          @article_cache ||= {}.compare_by_identity
          @article_cache.fetch(entry) do
            @article_cache[entry] = @extractor.new(
              entry.container, base_url: @url, selected_anchor: entry.selected_anchor
            ).call
          end
        end

        def deduplicate_by_destination(entries)
          destination_groups(entries).filter_map do |group|
            collapsed_group = collapse_nested_destination_group(group)
            collapsed_group.reduce do |best, entry|
              stronger_entry?(entry, best) ? entry : best
            end
          end
        end

        def destination_groups(entries)
          entries.group_by { entry_destination(_1) }.values
        end

        def collapse_nested_destination_group(entries)
          return entries if entries.size <= 1

          entries.reject do |entry|
            entries.any? do |other|
              next if entry.equal?(other)
              next unless nested_container_pair?(entry.container, other.container)

              stronger_entry?(other, entry)
            end
          end
        end

        def nested_container_pair?(left, right)
          left.ancestors.include?(right) || right.ancestors.include?(left)
        end

        def entry_destination(entry)
          entry.destination_facts&.destination || entry.article&.[](:url)&.to_s
        end

        def stable_rank(entries)
          entries.sort_by { |entry| [-entry.final_score, entry.position] }
        end

        def stronger_entry?(left, right) # rubocop:disable Metrics/AbcSize
          final_delta = left.final_score <=> right.final_score
          return final_delta.positive? unless final_delta.zero?

          quality_delta = left.quality_score <=> right.quality_score
          return quality_delta.positive? unless quality_delta.zero?

          left_article = entry_article(left)
          right_article = entry_article(right)
          return !right_article if !left_article || !right_article

          richness_delta = payload_richness_signature(left_article) <=> payload_richness_signature(right_article)
          richness_delta.zero? ? left.position < right.position : richness_delta.positive?
        end

        def payload_richness_signature(article)
          [
            article[:published_at] ? 1 : 0,
            word_count(article[:description]),
            article[:image] ? 1 : 0,
            Array(article[:categories]).length,
            Array(article[:enclosures]).length
          ]
        end
      end
    end
  end
end
