# frozen_string_literal: true

module Html2rss
  module Html
    class TitlePieces
      ##
      # Reads the nodes of one card for {TitlePieces}, SST and Nokogiri alike: element descendants, class
      # words, visible text and the element facts both title rules read (concealed, date and noise
      # elements), each read once per node. {SstNodes} and {NokogiriNodes} supply the reads that differ by
      # node kind; the headline rule stays on {TitlePieces}, the kicker rule on {Kicker}.
      class Nodes
        # Text that holds a word.
        WORD = /[[:alnum:]]/
        # Splits a class token into words.
        CLASS_WORD_BREAK = /[-_]+|(?<=[[:lower:][:digit:]])(?=[[:upper:]])/
        # +time+ element names of both node kinds.
        TIME_NAMES = Set['time', :time].freeze
        private_constant :CLASS_WORD_BREAK, :TIME_NAMES

        ##
        # @param root [Nokogiri::XML::Node, SST::Node] card root
        # @return [Nodes] the reader for the node kind of +root+
        def self.for(root) = root.instance_of?(SST::Node) ? SstNodes.new : NokogiriNodes.new

        def initialize
          @words = {}.compare_by_identity
          @elements = {}.compare_by_identity
          @texts = {}.compare_by_identity
        end

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Array] element descendants of +node+, read once per node
        def elements(node) = @elements[node] ||= descendants(node)

        ##
        # Lowercase words of all class tokens, plus each pair of neighbours joined (+region+ +Name+ gives
        # +regionname+, +sub+ +title+ gives +subtitle+).
        #
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Set<String>]
        def class_words(node)
          @words[node] ||= class_names(node).each_with_object(Set.new) do |token, words|
            parts = token.split(CLASS_WORD_BREAK).map(&:downcase)
            words.merge(parts).merge(parts.each_cons(2).map(&:join))
          end
        end

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Boolean] whether a sighted reader does not see +node+ ({Visibility.concealed?})
        def concealed?(node)
          Visibility.concealed?(class_names(node), style: style(node), hidden: !attribute(node, 'hidden').nil?)
        end

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
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
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Boolean]
        def dropped_date?(node)
          return false unless date_element?(node)

          before, after = texts_beside(node)
          !before.to_s.match?(WORD) && !after.to_s.match?(WORD)
        end

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Boolean] whether +node+ is a +time+ element or its class marks a date, time or duration
        #   ({DATE_WORDS})
        def date_element?(node) = TIME_NAMES.include?(node.name) || class_words(node).intersect?(DATE_WORDS)

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Array] elements of +node+ a reader does not see as its text: concealed and dropped date ones
        def unseen(node) = elements(node).select { concealed?(_1) || dropped_date?(_1) }

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Boolean] whether the text of +node+ is a paid-content label
        #   ({LinkDestination::Sponsorship.paid_text?})
        def paid_label?(node) = LinkDestination::Sponsorship.paid_text?(text(node))

        ##
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @return [Boolean] whether the text of +node+ is headline noise ({Article::Title.headline_noise_piece?})
        #   or a paid-content label
        def noise?(node)
          Article::Title.headline_noise_piece?(text(node)) || LinkDestination::Sponsorship.paid_text?(text(node))
        end
      end
      private_constant :Nodes
    end
  end
end
