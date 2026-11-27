# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Reads the fields of the items a feed config selected, for +selectors.items.enhance+. It normalizes the
    # part of the page the items need into an SST document once, maps each selected node onto it, and reads the
    # item with {AutoSource::ArticleExtractor::Item}.
    #
    # That part is the lowest element holding every item and the parent card each may walk to: an item reads
    # nothing above its parent card, and the chrome scope the region's ancestors give is seeded at its root, so
    # the result equals normalizing the whole page.
    #
    # It owns the documents' lifetime: an SST node finds its relationships through an index that only its
    # document keeps alive, so every document stays referenced here for as long as items are read.
    #
    # An item the region has no node for (inside a +template+ or +script+, after the closing +html+ tag, or
    # under a second root of a parsed JSON fragment: only the first root of a fragment is normalized) is read
    # from its own root, with the chrome scope its ancestors give it, so enhance never drops it. Such an item
    # has no parent card to walk to. An item that is a +template+ is read through its content. Only an item
    # that is a +script+, +style+, +svg+ or +iframe+ element, which has no card content, stays unread.
    #
    # The SST node is found by the parsed node's identity, which only a Nokogiri-parsed page offers. A parser
    # that does not keep node identity would need a document-order index here instead.
    class ItemEnhancer
      # @param items [Nokogiri::XML::NodeSet] the nodes selected from the parsed page
      # @param base_url [Html2rss::Url] base url used to resolve relative links
      # @param time_zone [String] channel time zone for naive dates
      # @param vocabulary [Vocabulary::Scope] the page language's scope
      def initialize(items, base_url:, time_zone:, vocabulary:)
        @items = items
        @base_url = base_url
        @time_zone = time_zone
        @vocabulary = vocabulary
        @alone = []
      end

      ##
      # @param item [Nokogiri::XML::Node] a node selected from the parsed page
      # @param url [Boolean] whether the item may supply its +url+; enhance fills fields only, so a +url+ is
      #   withheld from an item in page chrome (nav, header, footer) and when the config selects +url+ itself
      # @return [Hash{Symbol => Object}, nil] the item's extracted fields, +nil+ when it cannot be read
      def fields_for(item, url: true)
        root = document&.index&.node_for(item) || root_alone(item)
        return skipped(item) unless root

        segment = AutoSource::Segment.build(root_node: root, primary_link: root.find(&:link?), strategy: :list,
                                            position: 0)
        withhold_url(AutoSource::ArticleExtractor::Item.call(segment, base_url: @base_url, time_zone: @time_zone,
                                                                      link_resolver:), item, url)
      end

      private

      def withhold_url(fields, item, url)
        url && !chrome?(item) ? fields : fields&.except(:url)
      end

      def chrome?(item) = Html::Navigator.nokogiri_chrome_scope(item, @vocabulary) == :chrome

      # The region's one resolver: it owns the language's label reader, so a label is normalized once.
      def link_resolver
        @link_resolver ||= AutoSource::Scoring::LinkResolver.new(@base_url, vocabulary: @vocabulary)
      end

      # The SST document of the region, normalized for items.
      def document
        return @document if defined?(@document)

        root = region_root
        @document = root && normalize(root)
      end

      def normalize(root)
        Html::SST::Normalizer.call(root, vocabulary: @vocabulary, items: true, within: scope_above(root))
      end

      def scope_above(node) = node.parent ? Html::Navigator.nokogiri_chrome_scope(node.parent, @vocabulary) : :page

      # The lowest element above every item's walk end, +nil+ when the items share none (a fragment with
      # several roots).
      def region_root
        paths = @items.map { |item| path_to(walk_end(item)) }
        paths.reduce { |one, other| common_path(one, other) }&.reverse&.find(&:element?)
      end

      def path_to(node) = node.ancestors.reverse << node

      def common_path(one, other) = one.zip(other).take_while { |a, b| a == b }.map(&:first)

      # How far up the card walk can read from +item+: its nearest ancestor that is a usable card and holds
      # more than the item's own branch ({Html::CardWalk.thin_wrapper?}), else the topmost element. Both
      # decisions read the same facts as the walk in {AutoSource::ArticleExtractor}.
      def walk_end(item)
        branch = item
        while (parent = branch.parent)&.element?
          return parent if card_walk_stop?(parent, branch)

          branch = parent
        end
        branch
      end

      def card_walk_stop?(parent, branch)
        Html::Navigator.usable_card_parent?(parent, vocabulary: @vocabulary) &&
          parent.element_children.any? { |child| child != branch && kept?(child) }
      end

      def kept?(element) = Html::SST::Normalizer.kept_tag?(Html::Probe.tag(element), items: true)

      # The SST root of +item+ normalized by itself, kept alive with the rest, or +nil+ for an item that is no
      # SST node at all (a +script+, +style+, +svg+ or +iframe+ element).
      def root_alone(item)
        Log.event(:debug, 'selectors.enhance.alone', node: item.name)
        alone = normalize(item)
        @alone << alone if alone
        alone&.root
      end

      def skipped(item)
        Log.event(:debug, 'selectors.enhance.skipped', node: item.name)
        nil
      end
    end
  end
end
