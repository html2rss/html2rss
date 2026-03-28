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

        Entry = Data.define(
          :container,
          :selected_anchor,
          :quality_score,
          :junk_score,
          :final_score,
          :position,
          :article
        )

        CONTAINER_SELECTORS = [
          'article:not(:has(article))',
          'section:not(:has(section))',
          'li:not(:has(li))',
          'tr:not(:has(tr))',
          'div:not(:has(div))'
        ].freeze
        CONTENT_SEGMENTS = %w[
          article articles blog blogs changelog changelogs insight insights
          launch launches news post posts release releases story stories update updates
        ].to_set.freeze
        UTILITY_SEGMENTS = %w[
          about account archive archives author authors category categories comment comments
          contact feedback help newsletter newsletters profile search share signup subscribe
          tag tags topic topics
          feed feeds comment-feed comments-feed
          recommended
          for-you
          privacy terms cookie cookies
        ].to_set.freeze
        UTILITY_PREFIX_TEXT = /
          \A\s*(
            view\s+all|
            see\s+all|
            all\s+news|
            subscribe|
            newsletter|
            comment\s+feed|
            comments\s+feed
          )\b
        /ix
        HIGH_CONFIDENCE_JUNK_SEGMENTS = %w[
          about account archive archives author authors category categories comment comments
          contact cookie cookies feedback feed feeds help privacy profile search share signup
          subscribe tag tags terms topic topics comment-feed comments-feed
        ].to_set.freeze
        RECOMMENDED_TEXT = /\A\s*recommended(\s+for\s+you)?\b/i

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
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **_opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
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
          @extractable_entries ||= candidate_containers.each_with_index.filter_map do |container, position|
            selected_anchor = primary_anchor_for(container)
            next unless selected_anchor
            next if hard_junk_entry?(container, selected_anchor)

            quality = quality_score(container, selected_anchor)
            junk = junk_score(container, selected_anchor)

            Entry.new(
              container:,
              selected_anchor:,
              quality_score: quality,
              junk_score: junk,
              final_score: quality - junk,
              position:,
              article: nil
            )
          end
        end

        def ranked_entries
          @ranked_entries ||= begin
            entries = materialized_entries(extractable_entries)
            entries = deduplicate_by_destination(entries)
            entries = collapse_nested_destination_duplicates(entries)
            stable_rank(entries)
          end
        end

        def collect_candidate_containers
          seen = {}.compare_by_identity

          CONTAINER_SELECTORS.each_with_object([]) do |selector, containers|
            parsed_body.css(selector).each do |container|
              next if container.path.match?(Html::TAGS_TO_IGNORE)
              next if seen[container]

              seen[container] = true
              containers << container
            end
          end
        end

        private

        def quality_score(container, selected_anchor) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          words = word_count(title)
          destination = normalized_destination(selected_anchor)
          segments = destination&.path_segments || []
          container_text = visible_text(container)
          score = 0

          score += 40 if words >= 3
          score += 15 if words >= 7
          score += 20 if destination && destination.path.to_s.length > 6
          score += 15 if content_path?(segments)
          score += 15 if publish_marker?(container)
          score += 10 if descriptive_context?(container_text, title)
          score += 10 if article_container?(container)
          score
        end

        def junk_score(container, selected_anchor) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          destination = normalized_destination(selected_anchor)
          segments = destination&.path_segments || []
          utility_text = title.match?(UTILITY_PREFIX_TEXT)
          recommended_text = title.match?(RECOMMENDED_TEXT)
          non_content_utility_path = utility_path?(segments) && !content_path?(segments)
          shallow_destination = shallow_destination?(segments)
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          content_signal = content_path?(segments)
          weak_container = !publish_signal && !descriptive_signal
          score = 0

          score += 25 if non_content_utility_path
          score += 15 if utility_text && word_count(title) <= 6
          score += 10 if shallow_destination
          score += 10 if weak_container
          score += 10 if recommended_text && !content_signal
          score += 5 if explicit_junk_path?(segments)
          score
        end

        def hard_junk_entry?(container, selected_anchor) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          title = entry_title(container, selected_anchor)
          destination = normalized_destination(selected_anchor)
          segments = destination&.path_segments || []
          publish_signal = publish_marker?(container)
          descriptive_signal = descriptive_context?(visible_text(container), title)
          content_signal = content_path?(segments)
          weak_article_candidate = article_signal_count(
            container,
            publish_signal:,
            descriptive_signal:,
            content_signal:
          ) < 2

          explicit_junk_path?(segments) ||
            (title.match?(RECOMMENDED_TEXT) && shallow_destination?(segments) && weak_article_candidate) ||
            (title.match?(UTILITY_PREFIX_TEXT) && explicit_utility_destination?(segments) && weak_article_candidate)
        end

        def publish_marker?(container)
          container.at_css('time, [datetime], [itemprop="datePublished"], [itemprop="dateModified"]')
        end

        def article_signal_count(container, publish_signal:, descriptive_signal:, content_signal:)
          [article_container?(container), publish_signal, descriptive_signal, content_signal].count(true)
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

        def content_path?(segments)
          segments.any? do |segment|
            CONTENT_SEGMENTS.include?(segment) || segment.match?(/\A\d{4,}[\w-]*\z/)
          end
        end

        def utility_path?(segments)
          segments.any? { |segment| UTILITY_SEGMENTS.include?(segment) }
        end

        def explicit_junk_path?(segments)
          return false if segments.empty? || content_path?(segments)

          segments.any? { |segment| HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) }
        end

        def explicit_utility_destination?(segments)
          return false if segments.empty? || content_path?(segments)

          shallow_destination?(segments) && segments.any? { |segment| HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) }
        end

        def shallow_destination?(segments)
          segments.size <= 1 || (segments.size == 2 && HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segments.last))
        end

        def normalized_destination(anchor)
          href = anchor['href'].to_s.split('#').first.to_s.strip
          return if href.empty?

          Html2rss::Url.from_relative(href, @url)
        rescue ArgumentError
          nil
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

        def materialized_entries(entries) # rubocop:disable Metrics/MethodLength
          entries.filter_map do |entry|
            article = @extractor.new(
              entry.container,
              base_url: @url,
              selected_anchor: entry.selected_anchor
            ).call
            next unless article

            Entry.new(
              container: entry.container,
              selected_anchor: entry.selected_anchor,
              quality_score: entry.quality_score,
              junk_score: entry.junk_score,
              final_score: entry.final_score,
              position: entry.position,
              article:
            )
          end
        end

        def deduplicate_by_destination(entries) # rubocop:disable Metrics/CyclomaticComplexity
          by_destination = {}
          entries.each do |entry|
            destination = entry.article[:url]&.to_s || normalized_destination(entry.selected_anchor)&.to_s
            next unless destination

            current = by_destination[destination]
            by_destination[destination] = entry if current.nil? || stronger_entry?(entry, current)
          end
          by_destination.values
        end

        def collapse_nested_destination_duplicates(entries)
          entries.reject do |entry|
            entries.any? do |other|
              next if entry.equal?(other)
              next unless nested_container_pair?(entry.container, other.container)
              next unless same_destination?(entry, other)

              stronger_entry?(other, entry)
            end
          end
        end

        def nested_container_pair?(left, right)
          left.ancestors.include?(right) || right.ancestors.include?(left)
        end

        def same_destination?(left, right)
          normalized_destination(left.selected_anchor)&.to_s == normalized_destination(right.selected_anchor)&.to_s
        end

        def stable_rank(entries)
          entries.sort_by { |entry| [-entry.final_score, entry.position] }
        end

        def stronger_entry?(left, right) # rubocop:disable Metrics/AbcSize
          final_delta = left.final_score <=> right.final_score
          return final_delta.positive? unless final_delta.zero?

          quality_delta = left.quality_score <=> right.quality_score
          return quality_delta.positive? unless quality_delta.zero?

          richness_delta = payload_richness_signature(left.article) <=> payload_richness_signature(right.article)
          return richness_delta.positive? unless richness_delta.zero?

          left.position < right.position
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
