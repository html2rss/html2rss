# frozen_string_literal: true

module Html2rss
  class AutoSource
    class ArticleExtractor
      ##
      # Picks the kicker and the headline text of one teaser card: the one rule shared by
      # {ArticleExtractor} and {ArticleExtractor::Item}, so both give one title for the same
      # markup. The noise vocabulary and composition stay on {Article::Title}; rules: CONTEXT.md § Article title.
      #
      # Everything here reads elements, never headline wording:
      #
      # - Headline: a +data-title+ attribute on the heading or anchor wins. A heading or anchor made only of
      #   element pieces (no word in its own direct text) is read from its headline piece: its one outermost
      #   headline-marked descendant ({HEADLINE_WORDS}; never a sub-title or a label-marked one, {LABEL_WORDS}),
      #   else the selected anchor when it is the only link inside the heading. Pieces beside it (tags, dates,
      #   lead paragraphs) are no part of the title.
      # - Headline text leaves out the kicker, concealed elements ({Html::Visibility.concealed?}; they stay when they
      #   hold the only words, the accessible name of an otherwise empty link), date and time
      #   elements ({Nodes#dropped_date?}) unless direct text holding a word touches them, lead pieces
      #   ({LEAD_WORDS}), tag pieces closing the text ({TAG_WORDS}), clock-only or label-only elements before
      #   its first word, and date chips closing it ({#date_chip?}).
      # - A paid-content label ({LinkDestination::Sponsorship.paid_text?}) is item metadata, never title text:
      #   it is no kicker and leaves the headline text where it opens it, so a kept sponsored item (cleanup
      #   +keep_sponsored+) is titled by its headline alone. An ad word ("Anzeige", "Werbung") also names a
      #   topic and stays a kicker.
      # - Kicker: {Kicker}.
      class TitlePieces
        # Class words (tokens split on +-+, +_+ and camelCase, neighbours joined) marking kicker / eyebrow
        # text anywhere in the card.
        KICKER_WORDS = Set['kicker', 'eyebrow', 'pretitle', 'overline', 'topline'].freeze
        # Attribute marking kicker text.
        KICKER_ATTRIBUTE = 'data-tb-kicker'
        # Attribute holding the publisher's clean title on the heading or anchor.
        TITLE_ATTRIBUTE = 'data-title'
        # Class words (tokens split on +-+, +_+ and camelCase) marking the headline piece. +subTitle+ and
        # +sub-title+ are not one.
        HEADLINE_WORDS = Set['title', 'headline', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'].freeze
        # Class words of a label leaf that is a kicker when it opens the heading or anchor text.
        LABEL_WORDS = (KICKER_WORDS | Set['prefix', 'label', 'alert', 'alerte', 'live', 'regionname']).freeze
        # Class words of date, time and duration elements.
        DATE_WORDS = Set['date', 'time', 'duration', 'timestamp', 'datetime'].freeze
        # Class words of a teaser lead or summary, never part of the title.
        LEAD_WORDS = Set['lead', 'leadin', 'summary', 'excerpt', 'standfirst', 'dek', 'abstract'].freeze
        # Class words of tag or subtitle pieces, dropped when they close the headline text.
        TAG_WORDS = Set['tag', 'tags', 'subtitle'].freeze

        # Text that holds a word.
        WORD = Nodes::WORD
        # Text that holds a letter, which a clock time or punctuation does not.
        LETTER = /\p{L}/
        # Link element names of both node kinds.
        LINK_NAMES = Set['a', :a].freeze
        private_constant :WORD, :LETTER, :LINK_NAMES

        ##
        # @param root [SST::Node] card root
        # @param source [SST::Node, nil] headline source: the heading, else the anchor
        # @param anchor [SST::Node, nil] the card's selected anchor
        # @param vocabulary [Vocabulary::Scope] the page language's scope, read for kicker type markers
        def initialize(root, source, vocabulary:, anchor: nil)
          @anchor = anchor
          @vocabulary = vocabulary
          @nodes = Nodes.new(vocabulary)
          @kicker = Kicker.new(@nodes, root, source, vocabulary) { headline_piece(source) }
        end

        ##
        # @return [SST::Node, nil] the kicker element ({Kicker})
        def kicker = @kicker.element

        ##
        # @return [String, nil] kicker text without its noise pieces ({Article::Title.noise_piece?})
        def kicker_text = @kicker.text

        ##
        # @param node [SST::Node, nil] heading or anchor
        # @return [String, nil] its headline text (see the class notes)
        def headline_text(node)
          return unless node
          return @nodes.attribute(node, TITLE_ATTRIBUTE) if @nodes.attribute(node, TITLE_ATTRIBUTE).to_s.match?(WORD)

          node = headline_piece(node) || node
          @nodes.text(node, headline_drops(node))
        end

        ##
        # @param node [SST::Node, nil] heading or anchor
        # @return [Array<String>] texts of the pieces left out of its headline; the date chips among them
        #   still carry the card's date
        def dropped_texts(node)
          return [] unless node

          headline_drops(node).map { @nodes.text(_1).to_s }
        end

        private

        # --- Headline ------------------------------------------------------------------------------------

        # The piece of +node+ holding the headline when +node+ is made only of element pieces.
        def headline_piece(node)
          return if @nodes.own_words?(node)

          marked = @nodes.elements(node).select { headline_marked?(_1) }
          outermost = marked.reject { |el| marked.any? { |other| !other.equal?(el) && @nodes.inside?(el, other) } }
          return outermost.first if outermost.one?

          @anchor if sole_anchor_inside?(node)
        end

        # Whether the selected anchor is the only link inside +node+ (a headline split over several links
        # stays whole).
        def sole_anchor_inside?(node)
          links = @nodes.elements(node).select { LINK_NAMES.include?(_1.name) }
          links.one? && links.first.equal?(@anchor)
        end

        def headline_marked?(node)
          words = @nodes.class_words(node)
          words.intersect?(HEADLINE_WORDS) && !words.include?('subtitle') && !words.intersect?(LABEL_WORDS)
        end

        # Elements left out of the headline text of +node+, in rule order.
        def headline_drops(node)
          dropped = drop_concealed!(node, [kicker, *@nodes.elements(node).select { @nodes.dropped_date?(_1) }].compact)
          drop_pieces!(node, dropped, LEAD_WORDS) { |rest, _| rest.match?(WORD) }
          drop_pieces!(node, dropped, TAG_WORDS) { |rest, piece| rest.match?(WORD) && closing?(node, dropped, piece) }
          drop_opening_noise!(node, dropped)
          keep_words(node, drop_closing_dates!(node, dropped))
        end

        # Gives the headline back its own-term drops when, after all drops, no letter is left (a clock or a bar is
        # no word) or the text falls below the title floor ({AutoSource::Cleanup::MIN_WORDS}): a term of a
        # page-only language never empties or shortens a headline into rejection, whatever order its pieces
        # were dropped in.
        def keep_words(node, dropped)
          return dropped unless @vocabulary.own?

          left = @nodes.text(node, dropped).to_s
          return dropped if left.match?(LETTER) && WordCount.at_least?(left, AutoSource::Cleanup::MIN_WORDS)

          dropped.reject { @nodes.own_noise?(_1) }
        end

        # Concealed elements leave unless they hold the only words (the name of an otherwise empty link).
        def drop_concealed!(node, dropped)
          concealed = @nodes.elements(node).select { @nodes.concealed?(_1) }
          @nodes.text(node, dropped + concealed).to_s.match?(WORD) ? dropped.concat(concealed) : dropped
        end

        # Drops each +words+-marked piece of +node+ the block admits, given the text left without it.
        def drop_pieces!(node, dropped, words)
          @nodes.elements(node).each do |element|
            next unless @nodes.class_words(element).intersect?(words)

            dropped << element if yield(@nodes.text(node, dropped + [element]).to_s, element)
          end
        end

        def drop_opening_noise!(node, dropped)
          @nodes.elements(node).each do |element|
            next if within?(element, dropped) || !@nodes.noise?(element)
            break unless opening?(node, dropped, element)

            dropped << element
          end
        end

        # Date chips ({#date_chip?}) closing the text.
        def drop_closing_dates!(node, dropped)
          @nodes.elements(node).reverse_each do |element|
            next if within?(element, dropped) || !date_chip?(element)
            break unless closing?(node, dropped, element)

            dropped << element
          end
          dropped
        end

        # The date chip of a teaser card: a date-only element ({Article::Title.date_piece?}), or a date element
        # holding only a clock time (+late <time>22:10</time>+, while +at <b>20:15</b>+ is headline text).
        def date_chip?(element)
          @nodes.date_piece?(element) || (@nodes.date_element?(element) && Article::Title.clock_piece?(@nodes.text(element)))
        end

        # Whether +element+ opens the text of +node+ left after +dropped+.
        def opening?(node, dropped, element) = @nodes.text(node, dropped).to_s.start_with?(@nodes.text(element))

        # Whether +element+ closes the text of +node+ left after +dropped+.
        def closing?(node, dropped, element) = @nodes.text(node, dropped).end_with?(@nodes.text(element).to_s)

        # Whether +element+ is or sits inside a dropped element.
        def within?(element, dropped) = dropped.any? { @nodes.inside?(element, _1) }
      end
    end
  end
end
