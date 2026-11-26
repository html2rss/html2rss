# frozen_string_literal: true

module Html2rss
  class AutoSource
    class ArticleExtractor
      class TitlePieces
        ##
        # Reads the nodes of one card for {TitlePieces}: element descendants, class words, visible text and
        # the element facts both title rules read (concealed, date and noise elements), each read once per
        # node. Direct text is a node's lead text and the tail after each child. The headline rule stays on
        # {TitlePieces}, the kicker rule on {Kicker}.
        class Nodes
          # Text that holds a word.
          WORD = /[[:alnum:]]/
          # Splits a class token into words.
          CLASS_WORD_BREAK = /[-_]+|(?<=[[:lower:][:digit:]])(?=[[:upper:]])/
          # +time+ element names, as a symbol (SST) or a string.
          TIME_NAMES = Set['time', :time].freeze
          private_constant :CLASS_WORD_BREAK, :TIME_NAMES

          # @param vocabulary [Vocabulary::Scope] the page language's scope
          def initialize(vocabulary)
            @vocabulary = vocabulary
            @words = {}.compare_by_identity
            @elements = {}.compare_by_identity
            @texts = {}.compare_by_identity
          end

          ##
          # @param node [Html::SST::Node]
          # @return [Array] element descendants of +node+, read once per node
          def elements(node) = @elements[node] ||= descendants(node)

          ##
          # Lowercase words of all class tokens, plus each pair of neighbours joined (+region+ +Name+ gives
          # +regionname+, +sub+ +title+ gives +subtitle+).
          #
          # @param node [Html::SST::Node]
          # @return [Set<String>]
          def class_words(node)
            @words[node] ||= class_names(node).each_with_object(Set.new) do |token, words|
              parts = token.split(CLASS_WORD_BREAK).map(&:downcase)
              words.merge(parts).merge(parts.each_cons(2).map(&:join))
            end
          end

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether a sighted reader does not see +node+ ({Html::Visibility.concealed?})
          def concealed?(node)
            Html::Visibility.concealed?(class_names(node), style: style(node), hidden: !attribute(node, 'hidden').nil?)
          end

          ##
          # @param node [Html::SST::Node]
          # @param exclude [Array, nil] elements left out
          # @return [String, nil] visible text of +node+; text read without exclusions is read once per node
          def text(node, exclude = nil)
            return visible_text(node, exclude) if exclude&.any?

            @texts[node] ||= visible_text(node, nil)
          end

          ##
          # A date chip set apart from the headline words: a date element ({#date_element?}) with no direct text
          # holding a word right before or right after it (+resume on <time>Friday</time>+ is running text).
          #
          # @param node [Html::SST::Node]
          # @return [Boolean]
          def dropped_date?(node)
            return false unless date_element?(node)

            before, after = texts_beside(node)
            !before.to_s.match?(WORD) && !after.to_s.match?(WORD)
          end

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether +node+ is a +time+ element or its class marks a date, time or duration
          #   ({DATE_WORDS})
          def date_element?(node) = TIME_NAMES.include?(node.name) || class_words(node).intersect?(DATE_WORDS)

          ##
          # @param node [Html::SST::Node]
          # @return [Array] elements of +node+ a reader does not see as its text: concealed and dropped date ones
          def unseen(node) = elements(node).select { concealed?(_1) || dropped_date?(_1) }

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether the text of +node+ is a paid-content label
          #   ({LinkDestination::Sponsorship.paid_text?})
          def paid_label?(node) = LinkDestination::Sponsorship.paid_text?(text(node), vocabulary: @vocabulary)

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether the text of +node+ is headline noise ({Article::Title.headline_noise_piece?})
          #   or a paid-content label
          def noise?(node)
            Article::Title.headline_noise_piece?(text(node), vocabulary: @vocabulary,
                                                             date_element: dropped_date?(node)) ||
              paid_label?(node)
          end

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether +node+ is noise only through a term of a page-only language: a title piece
          #   ({Article::Title.own_noise_piece?}) or a paid label ({LinkDestination::Sponsorship.own_paid_text?})
          def own_noise?(node)
            Article::Title.own_noise_piece?(text(node), vocabulary: @vocabulary, date_element: dropped_date?(node)) ||
              LinkDestination::Sponsorship.own_paid_text?(text(node), vocabulary: @vocabulary)
          end

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether +node+ is a date chip by its text ({Article::Title.date_piece?})
          def date_piece?(node)
            Article::Title.date_piece?(text(node), vocabulary: @vocabulary, date_element: dropped_date?(node))
          end

          ##
          # @param root [Html::SST::Node]
          # @param attribute [String]
          # @return [Array<Html::SST::Node>] +root+ and its descendants carrying a class or +attribute+
          def carrying(root, attribute) = root.find_all { _1.attrs.class_names.any? || _1.attrs.raw.key?(attribute) }

          ##
          # @param node [Html::SST::Node]
          # @return [Array<String>] class tokens
          def class_names(node) = node.attrs.class_names

          ##
          # @param node [Html::SST::Node]
          # @param name [String]
          # @return [String, nil] the attribute value
          def attribute(node, name) = node.attrs.raw[name]

          ##
          # @param node [Html::SST::Node]
          # @return [Html::SST::Node, nil] the parent of an indexed node
          # @raise [Html::SST::Index::InvalidError] when +node+ has no live index
          def parent(node) = Html::SST::Index.for_node!(node).parent_of(node)

          ##
          # @param node [Html::SST::Node]
          # @param ancestor [Html::SST::Node]
          # @return [Boolean] whether +node+ is +ancestor+ or inside it
          def inside?(node, ancestor) = Html::SST::Index.descendant_or_self?(node, ancestor)

          ##
          # @param node [Html::SST::Node]
          # @return [Boolean] whether +node+'s direct text (outside its child elements) holds a word
          def own_words?(node) = node.own_text.match?(WORD)

          ##
          # @param node [Html::SST::Node]
          # @return [Array<Html::SST::Node>, nil] siblings before +node+, or nil when direct text holding a word
          #   sits between them and +node+
          def siblings_before(node)
            up = parent(node)
            index = up.children.index { _1.equal?(node) }
            up.children.take(index) unless [up.lead_text, *up.tails][..index].any? { _1.match?(WORD) }
          end

          private

          def descendants(node) = node.descendants
          def style(node) = node.attrs.style
          def visible_text(node, exclude) = node.visible_text(exclude:)

          # The direct text right before and right after +node+.
          def texts_beside(node)
            up = parent(node)
            return [] unless up

            [up.lead_text, *up.tails][up.children.index { _1.equal?(node) }, 2]
          end
        end
        private_constant :Nodes
      end
    end
  end
end
