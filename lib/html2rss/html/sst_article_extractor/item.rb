# frozen_string_literal: true

require 'zlib'

module Html2rss
  module Html
    class SstArticleExtractor
      ##
      # Reads the fields of an item a feed config selected (+selectors.items.enhance+), not of a card the
      # heuristic found. A configured item need not carry a link, a heading tag or an id, so where the
      # heuristic card reader would reject it, this one falls back: the title comes from the first heading
      # (else the heading-like node, else the first text), and the id from the DOM, else the title.
      # {#call} returns the field Hash for {Html2rss::Selectors} to merge under its explicit selectors; it
      # builds no {Article} and drops nothing.
      class Item < SstArticleExtractor
        # Attributes that label a node as the headline when the item has no heading tag.
        LABEL_ATTRIBUTES = %w[aria-label title].freeze
        # Tags that mark a headline when the item has no heading tag and no anchor.
        FALLBACK_HEADING_NAMES = Set[:strong, :b].freeze
        private_constant :LABEL_ATTRIBUTES, :FALLBACK_HEADING_NAMES

        class << self
          ##
          # @param segment [AutoSource::Segment] the configured item, as a segment of its own
          # @param base_url [String, Html2rss::Url]
          # @param time_zone [String, nil]
          # @param vocabulary [Vocabulary::Scope] the page language's scope
          # @return [Hash{Symbol => Object}] see {SstArticleExtractor#fields}
          def call(segment, base_url:, time_zone:, vocabulary:)
            resolver = Scoring::LinkResolver.new(base_url, vocabulary:)
            new(segment, base_url:, scraper: nil, time_zone:, link_resolver: resolver).call
          end
        end

        ##
        # @return [Hash{Symbol => Object}] see {SstArticleExtractor#fields}
        alias call fields

        private

        # The item's headline, below the item itself: its best heading tag, else the first node labelled by
        # +aria-label+ (then +title+), else, for an item without an anchor, the first bold or title-classed
        # node with text.
        def heading
          @heading ||= heading_tag || labelled_node || (fallback_heading unless @selected_anchor)
        end

        def heading_tag
          tags = @root.children.flat_map { |child| child.find_all(&:heading?) }
          select_best_heading(tags)
        end

        def labelled_node
          LABEL_ATTRIBUTES.each do |name|
            hit = descendant { |node| node.attrs.raw[name]&.match?(/\S/) }
            return hit if hit
          end
          nil
        end

        def fallback_heading
          descendant { |node| fallback_heading?(node) && node.visible_text }
        end

        def fallback_heading?(node)
          FALLBACK_HEADING_NAMES.include?(node.name) || node.attrs.class_names.any? { TITLE_CLASS_PATTERN.match?(_1) }
        end

        def descendant(&) = @root.find { |node| !node.equal?(@root) && yield(node) }

        # The text of the headline source, else the first text in the item.
        def title_from_in_card_sources
          source = heading || @selected_anchor
          source ? title_pieces.headline_text(source) : first_text(@root)
        end

        # The first non-blank text in document order, stripped.
        def first_text(node)
          lead = node.lead_text.strip
          return lead unless lead.empty?

          node.children.zip(node.tails).each do |child, tail|
            found = first_text(child) || tail.strip.then { _1 unless _1.empty? }
            return found if found
          end
          nil
        end

        # The item's DOM id, else its link path, else a slug of its heading text, else a hash of that text.
        def parse_id_from_dom
          nested = descendant { |node| node.attrs.id }
          candidates = [@root.attrs.id, nested&.attrs&.id]
          candidates << extract_url&.path
          candidates.compact.first || id_from_text
        end

        def id_from_text
          text = heading_text
          text && (slug(text) || Zlib.crc32(text).to_s(36))
        end

        def heading_text
          heading&.visible_text || first_text(@root)
        end

        def slug(text)
          slug = text.downcase.gsub(/[^a-z0-9]+/, '-').delete_prefix('-').delete_suffix('-')
          slug unless slug.empty?
        end
      end
    end
  end
end
