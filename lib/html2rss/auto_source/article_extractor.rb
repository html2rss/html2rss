# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Builds an {Html2rss::Article} from an SST segment / ranked segment.
    # {Item} reads a card a selector config picked.
    # rubocop:disable-next Metrics/ClassLength -- SST field extractors colocated
    class ArticleExtractor
      # Raised when the extractor is built without the segment it extracts from.
      class InvalidError < Html2rss::ContractError; end

      # CSS class tokens that mark title-like nodes. Broad on purpose: also shared with
      # {Html2rss::Curation::Capture::SelectorCandidates}, which owns no copy of it.
      TITLE_CLASS_PATTERN = /title|font-bold|font-semibold/
      # Nodes whose +srcset+ is an image source.
      SRCSET_NODES = Set[:img, :source, :picture].freeze
      # Nested blocks that mean a category node is actually a content container.
      CATEGORY_CONTAINER_NAMES = Set[:p, :article, :section].freeze

      class << self
        ##
        # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
        # @param base_url [String, Html2rss::Url]
        # @param scraper [Class, nil]
        # @param time_zone [String, nil] channel time zone for naive leftover dates; nil reads as UTC
        # @param link_resolver [Scoring::LinkResolver] the page's resolver, built for the same +base_url+;
        #   its already resolved URL of the primary link is reused instead of resolving it again, and it
        #   owns the page's +vocabulary+ (read for title type markers) and +text_classifier+ (the page-scoped
        #   label reader, so a label is normalized once)
        # @return [Html2rss::Article, nil] nil when the segment has no primary link (no URL of its own)
        def call(ranked_or_segment, base_url:, time_zone:, link_resolver:, scraper: nil)
          new(ranked_or_segment, base_url:, scraper:, time_zone:, link_resolver:).call
        end
      end

      # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
      # @param base_url [String, Html2rss::Url]
      # @param scraper [Class, nil]
      # @param time_zone [String, nil] channel time zone for naive leftover dates; nil reads as UTC
      # @param link_resolver [Scoring::LinkResolver] see {.call}
      def initialize(ranked_or_segment, base_url:, scraper:, time_zone:, link_resolver:)
        segment = ranked_or_segment.is_a?(Scoring::RankedSegment) ? ranked_or_segment.segment : ranked_or_segment
        raise InvalidError, 'segment is required' unless segment.is_a?(AutoSource::Segment)

        @root = segment.root_node
        @selected_anchor = segment.primary_link
        @base_url = base_url
        @scraper = scraper
        @time_zone = time_zone
        @link_resolver = link_resolver
        @vocabulary = link_resolver.vocabulary
        @classifier = link_resolver.text_classifier
      end

      ##
      # @return [Html2rss::Article, nil]
      def call
        return unless @selected_anchor

        article = Article.new(**fields, scraper: @scraper)
        article.valid? ? article : nil
      end

      ##
      # The card's article attributes, before {Article} validation.
      #
      # @return [Hash{Symbol => Object}]
      def fields # rubocop:disable Metrics/MethodLength
        title = title_from_in_card_sources
        lines = leftover_lines
        published_at = extract_published_at(lines) || title_chip_date
        root, lines, published_at = parent_card_fields(title, lines, published_at)
        {
          title: Article::Title.compose(title, kicker: title_pieces.kicker_text, vocabulary: @vocabulary),
          url: extract_url,
          image: extract_image,
          description: description_from(lines, title),
          id: parse_id_from_dom,
          published_at:, author: ArticleRules::Byline.first_author(lines),
          enclosures: extract_enclosures,
          categories: extract_categories(title, root:)
        }
      end

      private

      # Leftover text minus the lines a date already used; bylines are dropped by the description rule itself.
      def description_from(lines, title)
        ArticleRules::Description.from_lines(ArticleRules::Date.without_dates(lines),
                                             vocabulary: @vocabulary, title:, classifier: @classifier)
      end

      def extract_url
        @extract_url ||= @link_resolver.destination_facts(@selected_anchor)&.url
      end

      # Kicker and headline text ({TitlePieces}) of this card.
      def title_pieces
        @title_pieces ||= TitlePieces.new(@root, heading || @selected_anchor, anchor: @selected_anchor,
                                                                              vocabulary: @vocabulary)
      end

      # Prefer a non-junk headline ({Article} composes it with {#kicker_text}). A credit-only card
      # blanks to nil, and Cleanup drops the untitled item as +blank_title+. Other junk shapes stay
      # present so Cleanup rejects them under their own reason (slug, CMS, template).
      #
      # @return [String, nil]
      def title_from_in_card_sources
        candidates = title_candidates
        clean = candidates.find { |text| junk_reason(text).nil? }
        return clean if clean

        candidates.find { |text| junk_reason(text) != :credit }
      end

      def junk_reason(text) = AutoSource::Cleanup.junk_reason(text, vocabulary: @vocabulary, classifier: @classifier)

      # @return [Array<String>] ordered in-card title candidates (heading → anchor)
      def title_candidates
        [].tap do |candidates|
          add_title_candidate!(candidates, heading_title_text)
          add_title_candidate!(candidates, title_pieces.headline_text(@selected_anchor))
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

      # @return [String, nil] the heading's headline text ({TitlePieces#headline_text})
      def heading_title_text = title_pieces.headline_text(heading)

      def heading
        @heading ||= begin
          tags = @root.find_all(&:heading?)
          select_best_heading(tags) if tags.any?
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

      def leftover_lines
        leftover_lines_from(@root)
      end

      def leftover_lines_from(node)
        times = node.find_all { |n| n.name == :time }
        exclude = [heading, @selected_anchor, title_pieces.kicker, *times].compact
        lines = ArticleRules::Description.lines_from(node.visible_text(exclude:))
        lines + anchor_paragraphs(node, exclude - [@selected_anchor])
      end

      # An anchor inside the card stays out of the leftover text, and a lead paragraph can sit within it next to
      # the title; those paragraphs are read on their own. A paragraph the headline is built from (the title
      # reads the whole anchor when no piece is marked as the headline) is title, not description. An anchor
      # that is the card itself is read whole.
      def anchor_paragraphs(node, exclude)
        return [] if @selected_anchor.nil? || node.equal?(@selected_anchor)

        headline = title_from_in_card_sources.to_s
        paragraphs = @selected_anchor.find_all { |n| n.name == :p }
        lines = paragraphs.flat_map { |p| ArticleRules::Description.lines_from(p.visible_text(exclude:)) }
        lines.reject { |line| headline.include?(line) }
      end

      def heading_or_anchor_item?
        @root.heading? || @root.name == :a
      end

      def heading_or_anchor_miss?(title, lines, published_at)
        Html::CardWalk.miss?(
          heading_or_anchor_item: heading_or_anchor_item?,
          published_at:,
          description: ArticleRules::Description.from_lines(lines,
                                                            vocabulary: @vocabulary, title:, classifier: @classifier)
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
        Html::SST::Index.for_node!(@root).parent_until(parent, ->(node) { usable_walk_parent?(node) })
      end

      def usable_walk_parent?(node)
        Html::Navigator.usable_card_parent?(node, vocabulary: @vocabulary) && !thin_heading_wrapper?(node)
      end

      def thin_heading_wrapper?(node)
        Html::CardWalk.thin_wrapper?(
          children: node.children,
          item: @root,
          descendant_of: ->(item, child) { Html::SST::Index.descendant_or_self?(item, child) }
        )
      end

      def crowded_parent?(node)
        Html::CardWalk.crowded?(
          heading_count: node.each_node.count(&:heading?),
          distinct_main_hrefs: distinct_main_hrefs(node)
        )
      end

      def distinct_main_hrefs(node)
        node.each_node.filter_map { |candidate| candidate.attrs.href if candidate.link? }.uniq.size
      end

      def sst_parent
        Html::SST::Index.for_node!(@root).parent_of(@root)
      end

      # DOM id of the card (the root or its first descendant carrying one), else the link's path. The path is never
      # empty: a web URL has at least +/+, and an opaque URL (+mailto:+, +tel:+, +javascript:+) yields no article.
      # A hierarchical non-web URL (+ftp://x.com/a+) keeps its path; Cleanup drops it later.
      def parse_id_from_dom
        @root.find { |n| n.attrs.id }&.attrs&.id || extract_url&.path
      end

      def extract_image
        img_src = image_from_srcset || image_from_img || image_from_style || image_from_poster
        Url.resolve_web(img_src, @base_url)
      end

      def image_from_img
        @root.each_node.filter_map { |n| ArticleRules::Image.src_of(n) }.first
      end

      # A video's poster frame: the last resort, when the card has no other image.
      def image_from_poster
        @root.each_node.filter_map { |n| ArticleRules::Image.poster_of(n) }.first
      end

      def image_from_srcset
        srcsets = @root.find_all { |n| SRCSET_NODES.include?(n.name) && n.attrs.srcset }.map { |n| n.attrs.srcset }
        ArticleRules::Image.largest_from_srcsets(srcsets)
      end

      def image_from_style
        styles = @root.each_node.filter_map { |n| ArticleRules::Image.style_of(n) }
        ArticleRules::Image.best_from_styles(styles)
      end

      def extract_published_at(lines, root: @root)
        datetimes = root.each_node.map { |n| n.attrs.datetime }
        ArticleRules::Date.earliest(datetimes, leftover_lines: lines, time_zone: @time_zone)
      end

      # The date of a chip the headline title left out, when nothing else in the card dates it.
      def title_chip_date
        texts = [heading, @selected_anchor].flat_map { |n| title_pieces.dropped_texts(n) }
        ArticleRules::Date.earliest([], leftover_lines: texts, time_zone: @time_zone)
      end

      def extract_enclosures = ArticleRules::Enclosure.unique(collect_enclosures(@root, nil, []))

      # Depth-first in document order, carrying the nearest player ancestor's name for +source+ elements.
      def collect_enclosures(node, player, found)
        name = node.name.name
        attrs = node.attrs
        enclosure = ArticleRules::Enclosure.from_element(name, @base_url, src: attrs.src, href: attrs.href,
                                                                          type: attrs.type) { player }
        found << enclosure if enclosure
        player = name if ArticleRules::Enclosure::MEDIA_ELEMENTS.include?(name)
        node.children.each { |child| collect_enclosures(child, player, found) }
        found
      end

      def extract_categories(title, root: @root)
        ArticleRules::Category::Collector.new(vocabulary: @vocabulary, title:,
                                              classifier: @classifier).tap do |collector|
          root.find_all { |n| category_candidate?(n) }.each do |element|
            add_category_text!(collector, element) if category_text_node?(element, root)
            element.attrs.raw.each do |name, value|
              next unless ArticleRules::Category.attr_name_match?(name)

              collector.add(value)
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

      def add_category_text!(collector, element)
        return if category_text_container?(element)

        if element.link?
          collector.add(element.visible_text)
          return
        end

        add_descendant_or_visible_category!(collector, element)
      end

      def add_descendant_or_visible_category!(collector, element)
        anchors = element.find_all(&:link?)
        if anchors.any?
          anchors.each { |a| collector.add(a.visible_text) }
        else
          collector.add_split(element.visible_text)
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
