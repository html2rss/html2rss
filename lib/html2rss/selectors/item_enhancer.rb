# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Reads the fields of the items a feed config selected, for +selectors.items.enhance+. It normalizes the
    # parsed page into an SST document once, maps each selected node onto it, and reads the item with
    # {Html::SstArticleExtractor::Item}.
    #
    # It owns the documents' lifetime: an SST node finds its relationships through an index that only its
    # document keeps alive, so every document stays referenced here for as long as items are read.
    #
    # An item the page document has no node for (inside a +template+ or +script+, or under a second root of a
    # parsed JSON fragment: only the first root of a fragment is normalized) is read from its own root, with
    # the chrome scope its ancestors give it, so enhance never drops an item. Such an item has no parent card
    # to walk to.
    #
    # The SST node is found by the parsed node's identity, which only a Nokogiri-parsed page offers. A parser
    # that does not keep node identity would need a document-order index here instead.
    class ItemEnhancer
      # @param parsed_body [Nokogiri::XML::Node] the parsed page the items were selected from
      # @param base_url [Html2rss::Url] base url used to resolve relative links
      # @param time_zone [String] channel time zone for naive dates
      # @param vocabulary [Vocabulary::Scope] the page language's scope
      def initialize(parsed_body, base_url:, time_zone:, vocabulary:)
        @parsed_body = parsed_body
        @base_url = base_url
        @time_zone = time_zone
        @vocabulary = vocabulary
        @alone = []
      end

      ##
      # @param item [Nokogiri::XML::Node] a node selected from the parsed page
      # @return [Hash{Symbol => Object}, nil] the item's extracted fields, +nil+ when it cannot be read
      def fields_for(item)
        root = document&.index&.node_for(item) || root_alone(item)
        return skipped(item) unless root

        segment = AutoSource::Segment.build(root_node: root, primary_link: root.find(&:link?), strategy: :list,
                                            position: 0)
        Html::SstArticleExtractor::Item.call(segment, base_url: @base_url, time_zone: @time_zone,
                                                      vocabulary: @vocabulary)
      end

      private

      # The page's SST document, normalized for items.
      def document
        return @document if defined?(@document)

        @document = SST::Normalizer.call(@parsed_body, vocabulary: @vocabulary, items: true)
      end

      # The SST root of +item+ normalized by itself, kept alive with the rest, or +nil+ for an item that is no
      # SST node at all (a +script+ or +template+ element).
      def root_alone(item)
        Log.debug { { event_name: 'selectors.enhance.alone', node: item.name }.to_json }
        scope = item.parent ? Html::Navigator.nokogiri_chrome_scope(item.parent, @vocabulary) : :page
        alone = SST::Normalizer.call(item, vocabulary: @vocabulary, items: true, within: scope)
        @alone << alone if alone
        alone&.root
      end

      def skipped(item)
        Log.debug { { event_name: 'selectors.enhance.skipped', node: item.name }.to_json }
        nil
      end
    end
  end
end
