# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Leftover parent-card walk policy shared by Nokogiri and SST extractors.
    # Adapters traverse; this module decides miss / thin wrapper / crowded abort.
    # Keep/drop stays on {ArticleRules::Description}. Capture's selector lift is a
    # separate job (set-aware abort) and is not encoded here.
    module CardWalk
      class << self
        ##
        # @param heading_or_anchor_item [Boolean] true when the extract root is a heading or wrapping +a+
        # @param published_at [Object, nil]
        # @param description [String, nil] leftover description after Description keep/drop
        # @return [Boolean] whether to climb to a parent card
        def miss?(heading_or_anchor_item:, published_at:, description:)
          heading_or_anchor_item && published_at.nil? && description.nil?
        end

        ##
        # @param children [Enumerable] immediate children of the candidate parent
        # @param item [Object] heading/anchor being extracted
        # @param descendant_of [Proc] +(item, child)+ — whether +item+ sits inside +child+
        # @return [Boolean] true when the parent only wraps the item (no sibling content)
        def thin_wrapper?(children:, item:, descendant_of:)
          children.none? do |child|
            !child.equal?(item) && !descendant_of.call(item, child)
          end
        end

        ##
        # @param heading_count [Integer] headings inside the candidate parent
        # @param distinct_main_hrefs [Integer] unique eligible main-article hrefs
        # @return [Boolean] true when the parent looks like a listing, not one card
        def crowded?(heading_count:, distinct_main_hrefs:)
          heading_count > 1 || distinct_main_hrefs > 1
        end
      end
    end
  end
end
