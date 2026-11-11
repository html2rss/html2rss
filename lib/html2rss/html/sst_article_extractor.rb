# frozen_string_literal: true

require 'zlib'

module Html2rss
  module Html
    ##
    # Builds an {Html2rss::Article} from an SST segment / ranked segment.
    # Port of Html::ArticleExtractor field logic onto SST::Node.
    # rubocop:disable-next Metrics/ClassLength -- SST field extractors colocated for parity with ArticleExtractor
    class SstArticleExtractor
      # CSS class tokens that mark title-like nodes. Broad on purpose: also shared with
      # {Html2rss::SelectorCandidates}, which owns no copy of it.
      TITLE_CLASS_PATTERN = /title|font-bold|font-semibold/
      # A standalone "title" class token (+card-title+, +Teaser_title__x+), never +subtitle+, +sub-title+,
      # +sub_title+ or weight utilities. Used only to split a kicker-plus-title heading.
      HEADING_TITLE_TOKEN_PATTERN = /(?<![[:alnum:]])(?<!sub[-_])title(?![[:alnum:]])/i
      private_constant :HEADING_TITLE_TOKEN_PATTERN
      # Inline emphasis tags used as title fallbacks when no heading exists.
      FALLBACK_HEADING_NAMES = Set[:strong, :b].freeze
      # Nested blocks that mean a category node is actually a content container.
      CATEGORY_CONTAINER_NAMES = Set[:p, :article, :section].freeze

      class << self
        ##
        # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
        # @param base_url [String, Html2rss::Url]
        # @param scraper [Class, nil]
        # @param fallback_anchorless [Boolean]
        # @param time_zone [String] channel time zone for naive leftover dates
        # @return [Html2rss::Article, nil]
        def call(ranked_or_segment, base_url:, scraper: nil, fallback_anchorless: false, time_zone: 'UTC')
          new(ranked_or_segment, base_url:, scraper:, fallback_anchorless:, time_zone:).call
        end
      end

      # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
      # @param base_url [String, Html2rss::Url]
      # @param scraper [Class, nil]
      # @param fallback_anchorless [Boolean]
      # @param time_zone [String] channel time zone for naive leftover dates
      def initialize(ranked_or_segment, base_url:, scraper: nil, fallback_anchorless: false, time_zone: 'UTC')
        segment = ranked_or_segment.is_a?(Scoring::RankedSegment) ? ranked_or_segment.segment : ranked_or_segment
        raise ArgumentError, 'segment is required' unless segment.is_a?(AutoSource::Segment)

        @segment = segment
        @root = segment.root_node
        @selected_anchor = segment.primary_link
        @base_url = base_url
        @scraper = scraper
        @fallback_anchorless = fallback_anchorless
        @time_zone = time_zone
      end

      ##
      # @return [Html2rss::Article, nil]
      def call # rubocop:disable Metrics/MethodLength
        title = title_from_in_card_sources
        lines = leftover_lines
        published_at = extract_published_at(lines)
        root, lines, published_at = parent_card_fields(title, lines, published_at)
        attrs = {
          title:,
          kicker: title_pieces.kicker_text,
          url: extract_url,
          image: extract_image,
          description: ArticleRules::Description.from_lines(lines, title:),
          id: generate_id,
          published_at:,
          enclosures: extract_enclosures,
          categories: extract_categories(title, root:),
          scraper: @scraper,
          compose_title: true
        }
        article = Article.new(**attrs)
        article.valid? ? article : nil
      end

      private

      def extract_url
        @extract_url ||= begin
          href = @selected_anchor&.attrs&.href.to_s
          if href.empty?
            anchorless_url_fallback
          else
            Url.from_relative(href.split('#').first.strip, @base_url)
          end
        end
      end

      def anchorless_url_fallback
        return unless @fallback_anchorless

        id = generate_id
        Url.from_relative("##{id}", @base_url) if id
      end

      # Kicker and headline text ({TitlePieces}) of this card.
      def title_pieces = @title_pieces ||= TitlePieces.new(@root, heading || @selected_anchor)

      # Prefer a non-junk headline ({Article} composes it with {#kicker_text}). Credit-only cards
      # may blank to nil (description can carry the item). Other junk shapes must stay present so
      # Cleanup can hard-reject them — blanking slug/CMS/template text would admit titleless cards.
      #
      # @return [String, nil]
      def title_from_in_card_sources
        candidates = title_candidates
        clean = candidates.find { |text| AutoSource::Cleanup.junk_reason(text).nil? }
        return clean if clean

        candidates.find { |text| AutoSource::Cleanup.junk_reason(text) != :credit }
      end

      # @return [Array<String>] ordered in-card title candidates (heading → anchor → fallback)
      def title_candidates
        [].tap do |candidates|
          add_title_candidate!(candidates, heading_title_text)
          add_title_candidate!(candidates, title_pieces.headline_text(@selected_anchor))
          next unless candidates.empty? && @fallback_anchorless && @selected_anchor.nil?

          add_title_candidate!(candidates, first_nonempty_own_text)
        end
      end

      # @param candidates [Array<String>]
      # @param text [String, nil]
      # @return [void]
      def add_title_candidate!(candidates, text)
        stripped = text.to_s.strip
        return if stripped.empty? || candidates.include?(stripped)

        candidates << stripped
      end

      # @return [String, nil] the title child's text when the heading splits kicker and title, else the whole heading
      def heading_title_text = title_pieces.headline_text(title_child_of_heading || heading)

      # A heading made only of child elements (no stray text) where exactly one carries a title
      # class (and no kicker class) is a kicker-plus-title split; that child alone is the title.
      #
      # @return [SST::Node, nil]
      def title_child_of_heading
        return if heading.nil? || heading.own_text.match?(/\S/)

        titled = heading.children.select { |child| title_token_child?(child) }
        titled.first if titled.one?
      end

      def title_token_child?(child)
        classes = child.attrs.class_names
        classes.any?(HEADING_TITLE_TOKEN_PATTERN) && classes.none?(TitlePieces::KICKER_CLASS)
      end

      def heading
        @heading ||= begin
          tags = @root.find_all(&:heading?)
          if tags.any?
            select_best_heading(tags)
          elsif @fallback_anchorless && @selected_anchor.nil?
            fallback_heading
          end
        end
      end

      def select_best_heading(tags)
        min_name = tags.map { |t| t.name.to_s }.min
        best = nil
        max_size = -1
        tags.each do |tag|
          next unless tag.name.to_s == min_name

          size = tag.visible_text.to_s.size
          (best = tag) && (max_size = size) if size > max_size
        end
        best
      end

      def fallback_heading
        @root.find do |n|
          next true if FALLBACK_HEADING_NAMES.include?(n.name)

          n.attrs.class_names.any?(TITLE_CLASS_PATTERN) &&
            !n.visible_text.to_s.strip.empty?
        end
      end

      def descendant_of?(child, ancestor)
        return true if child.equal?(ancestor)

        if (index = SST::Index.for_node(child))
          return index.descendant_of?(child, ancestor)
        end

        !ancestor.find { |d| d.equal?(child) }.nil?
      end

      def leftover_lines
        leftover_lines_from(@root)
      end

      def leftover_lines_from(node)
        times = node.find_all { |n| n.name == :time }
        exclude = [heading, @selected_anchor, title_pieces.kicker, *times].compact
        ArticleRules::Description.lines_from(node.visible_text(exclude:))
      end

      def heading_or_anchor_item?
        @root.heading? || @root.name == :a
      end

      def heading_or_anchor_miss?(title, lines, published_at)
        CardWalk.miss?(
          heading_or_anchor_item: heading_or_anchor_item?,
          published_at:,
          description: ArticleRules::Description.from_lines(lines, title:)
        )
      end

      def parent_card_fields(title, lines, published_at)
        return @root, lines, published_at unless heading_or_anchor_miss?(title, lines, published_at)

        parent = immediate_card_parent
        if !parent || crowded_parent?(parent)
          Log.debug { "parent-walk abort at #{sst_parent&.name}" }
          return @root, lines, published_at
        end

        new_lines = leftover_lines_from(parent)
        new_date = extract_published_at(new_lines, root: parent)
        [parent, new_lines, new_date || published_at]
      end

      def immediate_card_parent
        parent = sst_parent
        index = SST::Index.for_node(@root)
        index&.parent_until(parent, ->(node) { usable_walk_parent?(node) })
      end

      def usable_walk_parent?(node)
        Navigator.usable_card_parent?(node) && !thin_heading_wrapper?(node)
      end

      def thin_heading_wrapper?(node)
        CardWalk.thin_wrapper?(
          children: node.children,
          item: @root,
          descendant_of: ->(item, child) { descendant_of?(item, child) }
        )
      end

      def crowded_parent?(node)
        CardWalk.crowded?(
          heading_count: node.each_node.count(&:heading?),
          distinct_main_hrefs: distinct_main_hrefs(node)
        )
      end

      def distinct_main_hrefs(node)
        node.each_node.filter_map { |candidate| candidate.attrs.href if candidate.link? }.uniq.size
      end

      def sst_parent
        SST::Index.for_node(@root)&.parent_of(@root)
      end

      def generate_id # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        @generate_id ||= begin
          id_from_dom = parse_id_from_dom
          if id_from_dom
            id_from_dom
          else
            heading_text = heading&.visible_text
            heading_text = first_nonempty_own_text if heading_text.to_s.strip.empty? && @fallback_anchorless
            if heading_text && !heading_text.strip.empty?
              generate_slug(heading_text)
            elsif @fallback_anchorless
              text = @root.visible_text.to_s.strip
              Zlib.crc32(text).to_s(36) unless text.empty?
            end
          end
        end
      end

      def parse_id_from_dom
        candidates = [@root.attrs.id]
        nested = @root.find { |n| n.attrs.id }
        candidates << nested.attrs.id if nested
        if @selected_anchor
          url = extract_url
          candidates += [url&.path, url&.query]
        end
        candidates.compact.reject(&:empty?).first
      end

      def generate_slug(text)
        slug = text.downcase.gsub(/[^a-z0-9]+/, '-')
        slug = slug[1..] if slug.start_with?('-')
        slug = slug[0..-2] if slug.end_with?('-')
        slug unless slug.empty?
      end

      def first_nonempty_own_text
        @root.find { |n| !n.own_text.to_s.strip.empty? }&.own_text&.strip
      end

      def extract_image
        img_src = image_from_srcset || image_from_img || image_from_style
        Url.from_relative(img_src, @base_url) if img_src
      end

      def image_from_img
        @root.find { |n| n.image? && n.attrs.src && !n.attrs.src.start_with?('data:') }&.attrs&.src
      end

      def image_from_srcset
        srcsets = @root.find_all { |n| n.attrs.srcset }.map { |n| n.attrs.srcset }
        ArticleRules::Image.largest_from_srcsets(srcsets)
      end

      def image_from_style
        styles = @root.find_all { |n| n.attrs.style&.include?('url') }.map { |n| n.attrs.style }
        ArticleRules::Image.best_from_styles(styles)
      end

      def extract_published_at(lines, root: @root)
        datetimes = root.find_all { |n| n.attrs.datetime }.map { |n| n.attrs.datetime }
        ArticleRules::Date.earliest(datetimes, leftover_lines: lines, time_zone: @time_zone)
      end

      def extract_enclosures
        @root.find_all { |n| enclosure_node?(n) }.filter_map { |element| enclosure_from(element) }
      end

      def enclosure_node?(node)
        case node.name
        when :img then node.attrs.src && !node.attrs.src.start_with?('data:')
        when :source, :audio, :video, :iframe then node.attrs.src
        when :a then ArticleRules::Enclosure.archive_href?(node.attrs.href)
        else false
        end
      end

      def enclosure_from(element)
        case element.name
        when :img
          ArticleRules::Enclosure.from_image(element.attrs.src, @base_url)
        when :video, :audio, :source
          ArticleRules::Enclosure.from_media(element.attrs.src, element.attrs.type, @base_url)
        when :iframe
          ArticleRules::Enclosure.from_iframe(element.attrs.src, @base_url)
        when :a
          ArticleRules::Enclosure.from_anchor(element.attrs.href, @base_url)
        end
      end

      def extract_categories(title, root: @root)
        Set.new.tap do |categories|
          root.find_all { |n| category_candidate?(n) }.each do |element|
            add_category_text!(categories, element, title:) if category_text_node?(element, root)
            element.attrs.raw.each do |name, value|
              next unless ArticleRules::Category.attr_name_match?(name)

              ArticleRules::Category.add_text!(categories, value, title:)
            end
          end
        end.to_a
      end

      def category_candidate?(node)
        ArticleRules::Category.class_match?(node.attrs.class_names) ||
          node.attrs.raw.any? { |k, _| ArticleRules::Category.attr_name_match?(k) }
      end

      def category_text_node?(element, root)
        !element.equal?(root) && ArticleRules::Category.class_match?(element.attrs.class_names)
      end

      def add_category_text!(categories, element, title:)
        return if category_text_container?(element)

        if element.link?
          ArticleRules::Category.add_text!(categories, element.visible_text, title:)
          return
        end

        add_descendant_or_visible_category!(categories, element, title:)
      end

      def add_descendant_or_visible_category!(categories, element, title:)
        anchors = element.find_all(&:link?)
        if anchors.any?
          anchors.each { |a| ArticleRules::Category.add_text!(categories, a.visible_text, title:) }
        else
          ArticleRules::Category.add_split_text!(categories, element.visible_text, title:)
        end
      end

      def category_text_container?(element)
        element.find do |node|
          next if node.equal?(element)

          node.heading? || CATEGORY_CONTAINER_NAMES.include?(node.name)
        end
      end
    end
  end
end
