# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Picks the kicker and the headline text of one teaser card: the one rule shared by
    # {ArticleExtractor} (Nokogiri) and {SstArticleExtractor} (SST), so both give one title for the same
    # markup. The noise vocabulary and composition stay on {Article::Title}; rules: CONTEXT.md § Article title.
    #
    # Everything here reads elements, never headline wording:
    #
    # - Headline: a +data-title+ attribute on the heading or anchor wins. A heading or anchor made only of
    #   element pieces (no word in its own direct text) is read from its headline piece: its one outermost
    #   headline-marked descendant ({HEADLINE_WORDS}; never a sub-title or a label-marked one, {LABEL_WORDS}),
    #   else the selected anchor when it is the only link inside the heading. Pieces beside it (tags, dates,
    #   lead paragraphs) are no part of the title.
    # - Headline text leaves out the kicker, concealed elements ({Visibility.concealed?}; they stay when they
    #   hold the only words, the accessible name of an otherwise empty link), date and time
    #   elements ({#date_element?}) unless they sit inside running text, lead pieces ({LEAD_WORDS}), tag
    #   pieces closing the text ({TAG_WORDS}), clock-only or label-only elements before its first word, and
    #   date-only elements ({Article::Title.date_piece?}) closing it.
    # - A paid-content label ({LinkDestination::Sponsorship.paid_text?}) is item metadata, never title text:
    #   it is no kicker and leaves the headline text where it opens it, so a kept sponsored item (cleanup
    #   +keep_sponsored+) is titled by its headline alone. An ad word ("Anzeige", "Werbung") also names a
    #   topic and stays a kicker.
    # - Kicker, first match: the outermost kicker-marked element beside the headline ({KICKER_CLASS},
    #   {KICKER_ATTRIBUTE}) holding no word besides its noise and kicker-marked parts; else a label leaf
    #   ({LABEL_WORDS}) opening the heading or anchor text; else the piece right before the headline piece.
    class TitlePieces # rubocop:disable Metrics/ClassLength
      # Class-token marks of kicker / eyebrow text anywhere in the card.
      KICKER_CLASS = /kicker|eyebrow|pre-title|pretitle|overline|topline/i
      # Attribute marking kicker text.
      KICKER_ATTRIBUTE = 'data-tb-kicker'
      # Attribute holding the publisher's clean title on the heading or anchor.
      TITLE_ATTRIBUTE = 'data-title'
      # Class words (tokens split on +-+, +_+ and camelCase) marking the headline piece. +subTitle+ and
      # +sub-title+ are not one.
      HEADLINE_WORDS = Set['title', 'headline', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'].freeze
      # Class words of a label leaf that is a kicker when it opens the heading or anchor text.
      LABEL_WORDS = Set['kicker', 'eyebrow', 'overline', 'pretitle', 'topline', 'prefix', 'label', 'alert', 'alerte',
                        'live', 'regionname'].freeze
      # Class words of date, time and duration elements.
      DATE_WORDS = Set['date', 'time', 'duration', 'timestamp', 'datetime'].freeze
      # Class words of a teaser lead or summary, never part of the title.
      LEAD_WORDS = Set['lead', 'leadin', 'summary', 'excerpt', 'standfirst', 'dek', 'abstract'].freeze
      # Class words of tag or subtitle pieces, dropped when they close the headline text.
      TAG_WORDS = Set['tag', 'tags', 'subtitle'].freeze

      # Text that holds a word.
      WORD = /[[:alnum:]]/
      # Splits a class token into words.
      CLASS_WORD_BREAK = /[-_]+|(?<=[[:lower:][:digit:]])(?=[[:upper:]])/
      # +time+ element names of both node kinds.
      TIME_NAMES = Set['time', :time].freeze
      # Media element names of both node kinds: a piece holding one is a picture, not a kicker.
      MEDIA_NAMES = Set['img', 'picture', 'figure', 'video', 'svg', :img, :picture, :figure, :video, :svg].freeze
      # Paragraphs of both node kinds: running prose, never a kicker.
      PARAGRAPH_NAMES = Set['p', :p].freeze
      # Link element names of both node kinds.
      LINK_NAMES = Set['a', :a].freeze
      private_constant :WORD, :CLASS_WORD_BREAK, :TIME_NAMES, :MEDIA_NAMES, :PARAGRAPH_NAMES, :LINK_NAMES

      ##
      # @param root [Nokogiri::XML::Node, SST::Node] card root
      # @param source [Nokogiri::XML::Node, SST::Node, nil] headline source: the heading, else the anchor
      # @param anchor [Nokogiri::XML::Node, SST::Node, nil] the card's selected anchor
      def initialize(root, source, anchor: nil)
        @root = root
        @source = source
        @anchor = anchor
        @sst = root.instance_of?(SST::Node)
        @words = {}.compare_by_identity
        @elements = {}.compare_by_identity
        @texts = {}.compare_by_identity
        @kicker = marked_kicker || (label_kicker || preceding_kicker if @source)
      end

      ##
      # @return [Nokogiri::XML::Node, SST::Node, nil] the kicker element
      attr_reader :kicker

      ##
      # @return [String, nil] kicker text without its noise pieces ({Article::Title.noise_piece?})
      def kicker_text = kicker && text_without_noise(kicker)

      ##
      # @param node [Nokogiri::XML::Node, SST::Node, nil] heading or anchor
      # @return [String, nil] its headline text (see the class notes)
      def headline_text(node)
        return unless node
        return attribute(node, TITLE_ATTRIBUTE) if attribute(node, TITLE_ATTRIBUTE).to_s.match?(WORD)

        node = headline_piece(node) || node
        text(node, headline_drops(node))
      end

      private

      # --- Headline ------------------------------------------------------------------------------------

      # The piece of +node+ holding the headline when +node+ is made only of element pieces.
      def headline_piece(node)
        return if own_words?(node)

        marked = elements(node).select { headline_marked?(_1) }
        outermost = marked.reject { |el| marked.any? { |other| !other.equal?(el) && inside?(el, other) } }
        return outermost.first if outermost.one?

        @anchor if sole_anchor_inside?(node)
      end

      # Whether the selected anchor is the only link inside +node+ (a headline split over several links
      # stays whole).
      def sole_anchor_inside?(node)
        links = elements(node).select { LINK_NAMES.include?(_1.name) }
        links.one? && links.first.equal?(@anchor)
      end

      def headline_marked?(node)
        words = class_words(node)
        words.intersect?(HEADLINE_WORDS) && !words.include?('subtitle') && !words.intersect?(LABEL_WORDS)
      end

      # Elements left out of the headline text of +node+, in rule order.
      def headline_drops(node)
        dropped = drop_concealed!(node, [kicker, *elements(node).select { dropped_date?(_1) }])
        drop_pieces!(node, dropped, LEAD_WORDS) { |rest, _| rest.match?(WORD) }
        drop_pieces!(node, dropped, TAG_WORDS) { |rest, piece| rest.match?(WORD) && closing?(node, dropped, piece) }
        drop_opening_noise!(node, dropped)
        drop_closing_dates!(node, dropped)
      end

      # Concealed elements leave unless they hold the only words (the name of an otherwise empty link).
      def drop_concealed!(node, dropped)
        concealed = elements(node).select { concealed?(_1) }
        text(node, dropped + concealed).to_s.match?(WORD) ? dropped.concat(concealed) : dropped
      end

      # Drops each +words+-marked piece of +node+ the block admits, given the text left without it.
      def drop_pieces!(node, dropped, words)
        elements(node).each do |element|
          next unless class_words(element).intersect?(words)

          dropped << element if yield(text(node, dropped + [element]).to_s, element)
        end
      end

      def drop_opening_noise!(node, dropped)
        elements(node).each do |element|
          next if dropped.include?(element) || !noise_text?(text(element))
          break unless opening?(node, dropped, element)

          dropped << element
        end
        dropped
      end

      # A date-only element ({Article::Title.date_piece?}) closing the text: the date chip of a teaser card.
      def drop_closing_dates!(node, dropped)
        elements(node).reverse_each do |element|
          next if dropped.include?(element) || !Article::Title.date_piece?(text(element))
          break unless closing?(node, dropped, element)

          dropped << element
        end
        dropped
      end

      # Whether +element+ opens the text of +node+ left after +dropped+.
      def opening?(node, dropped, element) = text(node, dropped).to_s.start_with?(text(element))

      # Whether +element+ closes the text of +node+ left after +dropped+.
      def closing?(node, dropped, element) = text(node, dropped).end_with?(text(element).to_s)

      # --- Kicker --------------------------------------------------------------------------------------

      # A kicker inside the heading or anchor wins over one beside it (a topline in the heading over a
      # type badge above it).
      def marked_kicker
        candidates = marked.select { kicker_text?(_1) && beside_headline?(_1) }
        kickers = candidates.select { |node| parts_only?(node, candidates) }
        kickers.find { inside?(_1, @source) } || kickers.first
      end

      # A label leaf opening the source text, with headline text after it.
      def label_kicker
        rest = text(@source, unseen(@source)).to_s
        elements(@source).find { label_leaf?(_1) && opening_kicker?(_1, rest) }
      end

      # A label-marked element that is no paid-content label.
      def label_leaf?(element) = class_words(element).intersect?(LABEL_WORDS) && !paid_label?(element)

      # Whether +element+ opens +rest+, the source text, with headline words after it.
      def opening_kicker?(element, rest)
        rest.start_with?(text(element).to_s) && text(@source, unseen(@source) + [element]).to_s.match?(WORD)
      end

      # The nearest worded piece before the source's headline piece, when it is a kicker-shaped leaf.
      def preceding_kicker
        candidate = piece_before(headline_piece(@source))
        return unless candidate && kicker_shaped?(candidate)

        leaf = nearest_leaf(candidate)
        leaf if kicker_shaped?(leaf)
      end

      # Walks from +piece+ up to the source, looking back over element siblings; direct text stops it.
      def piece_before(piece)
        current = piece
        until current.nil? || current.equal?(@source)
          before = siblings_before(current)
          return if before.nil?

          worded = before.reverse.find { |sibling| !skipped_piece?(sibling) }
          return worded if worded

          current = parent(current)
        end
      end

      # Descends into the last worded child of a piece made only of elements: the leaf next to the
      # headline (a topic span after a badge in one box).
      def nearest_leaf(node)
        while !own_words?(node) && (child = node.children.reverse.find { !skipped_piece?(_1) })
          node = child
        end
        node
      end

      def skipped_piece?(node) = concealed?(node) || date_element?(node) || !text_without_noise(node).to_s.match?(WORD)

      def kicker_shaped?(node)
        !PARAGRAPH_NAMES.include?(node.name) && !class_words(node).intersect?(LEAD_WORDS) &&
          elements(node).none? { MEDIA_NAMES.include?(_1.name) }
      end

      def kicker_text?(node)
        !noise_element?(node) && !concealed?(node) && text_without_noise(node).to_s.match?(WORD)
      end

      def text_without_noise(node) = text(node, kicker_noise(node))

      # Kicker pieces that are noise on their own: date and time elements, concealed elements and
      # {Article::Title.noise_piece?}.
      def kicker_noise(node)
        elements(node).select { date_element?(_1) || concealed?(_1) || paid_label?(_1) || Article::Title.noise_piece?(text(_1)) }
      end

      def noise_element?(node) = date_element?(node) || noise_text?(text(node))

      # Headline noise ({Article::Title.headline_noise_piece?}) or a paid-content label.
      def noise_text?(text)
        Article::Title.headline_noise_piece?(text) || LinkDestination::Sponsorship.paid_text?(text)
      end

      def paid_label?(node) = LinkDestination::Sponsorship.paid_text?(text(node))

      def beside_headline?(node)
        return true unless @source
        return false if inside?(@source, node)

        !inside?(node, @source) || text(@source, [node]).to_s.match?(WORD)
      end

      # Whether +node+ holds no word outside its noise and its nested kicker candidates.
      def parts_only?(node, candidates)
        parts = candidates.select { |other| !other.equal?(node) && inside?(other, node) }
        return true if parts.empty?

        !text(node, kicker_noise(node) + parts).to_s.match?(WORD)
      end

      # --- Element facts -------------------------------------------------------------------------------

      # Elements of +node+ a reader does not see as text of it: concealed and dropped date elements.
      def unseen(node) = elements(node).select { concealed?(_1) || dropped_date?(_1) }

      # A +time+ element or an element whose class marks a date, time or duration ({DATE_WORDS}).
      def date_element?(node) = TIME_NAMES.include?(node.name) || class_words(node).intersect?(DATE_WORDS)

      # Date elements leave the headline unless they sit inside running text (+moved to <time>Friday</time>
      # after+): a word in the direct text right before and right after them.
      def dropped_date?(node) = date_element?(node) && !running_text?(node)

      # Whether a sighted reader does not see +node+ ({Visibility.concealed?}).
      def concealed?(node)
        style = @sst ? node.attrs.style : node['style']
        Visibility.concealed?(class_names(node), style:, hidden: !attribute(node, 'hidden').nil?)
      end

      def kicker_marked?(node) = attribute(node, KICKER_ATTRIBUTE) || class_names(node).any?(KICKER_CLASS)

      # Lowercase words of all class tokens, plus each pair of neighbours joined (+region+ +Name+ gives
      # +regionname+, +sub+ +title+ gives +subtitle+).
      def class_words(node)
        @words[node] ||= class_names(node).each_with_object(Set.new) do |token, words|
          parts = token.split(CLASS_WORD_BREAK).map(&:downcase)
          words.merge(parts).merge(parts.each_cons(2).map(&:join))
        end
      end

      # --- Node reads: SST nodes or Nokogiri nodes -----------------------------------------------------

      def marked
        return @root.find_all { kicker_marked?(_1) } if @sst

        @root.xpath('descendant-or-self::*[@class or @data-tb-kicker]').select { kicker_marked?(_1) }
      end

      # Element descendants of +node+, read once per node.
      def elements(node) = @elements[node] ||= @sst ? node.descendants : node.css('*')
      def class_names(node) = @sst ? node.attrs.class_names : node['class'].to_s.split
      def attribute(node, name) = @sst ? node.attrs.raw[name] : node[name]

      def parent(node) = @sst ? SST::Index.for_node(node)&.parent_of(node) : node.parent

      # Visible text of +node+ without +exclude+ elements; text read without exclusions is read once per node.
      def text(node, exclude = nil)
        return visible_text(node, exclude) if exclude&.any?

        @texts[node] ||= visible_text(node, nil)
      end

      def visible_text(node, exclude)
        @sst ? node.visible_text(exclude:) : Navigator.extract_visible_text(node, exclude_nodes: exclude)
      end

      # Whether +node+ is +ancestor+ or inside it.
      def inside?(node, ancestor)
        return SST::Index.descendant_or_self?(node, ancestor) if @sst

        node == ancestor || Navigator.descendant_of?(node, ancestor)
      end

      # Whether +node+'s own direct text (outside its child elements) holds a word.
      def own_words?(node)
        return node.own_text.match?(WORD) if @sst

        node.children.any? { _1.text? && _1.text.match?(WORD) }
      end

      # Siblings before +node+, or nil when a word in direct text sits between them and +node+.
      def siblings_before(node)
        @sst ? sst_siblings_before(node) : nokogiri_siblings_before(node)
      end

      def sst_siblings_before(node)
        up = parent(node)
        return unless up

        index = up.children.index { _1.equal?(node) }
        up.children.take(index) unless [up.lead_text, *up.tails][..index].any? { _1.match?(WORD) }
      end

      def nokogiri_siblings_before(node)
        before = []
        sibling = node.previous_sibling
        while sibling
          return if sibling.text? && sibling.text.match?(WORD)

          before.unshift(sibling)
          sibling = sibling.previous_sibling
        end
        before
      end

      # Whether +node+ sits inside running text: a word in the direct text right before and after it.
      def running_text?(node)
        @sst ? sst_running_text?(node) : nokogiri_running_text?(node)
      end

      def sst_running_text?(node)
        up = parent(node)
        return false unless up

        index = up.children.index { _1.equal?(node) }
        before, after = [up.lead_text, *up.tails][index, 2]
        before.match?(WORD) && after.match?(WORD)
      end

      def nokogiri_running_text?(node)
        before = node.previous_sibling
        after = node.next_sibling
        before&.text? && after&.text? && before.text.match?(WORD) && after.text.match?(WORD)
      end
    end
  end
end
