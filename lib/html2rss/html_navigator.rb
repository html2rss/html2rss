# frozen_string_literal: true

module Html2rss
  ##
  # HtmlNavigator provides methods to navigate through HTML nodes.
  class HtmlNavigator
    class << self
      ##
      # Returns the first parent that satisfies the condition.
      # If the condition is met, it returns the node itself.
      #
      # @param node [Nokogiri::XML::Node] The node to start the search from.
      # @param condition [Proc] The condition to be met.
      # @return [Nokogiri::XML::Node, nil] The first parent that satisfies the condition.
      def parent_until_condition(node, condition)
        while node && !node.document? && node.name != 'html'
          return node if condition.call(node)

          node = node.parent
        end
      end

      ##
      # Think of it as `css_upwards` method.
      # It searches for the closest parent that matches the given selector.
      def find_closest_selector_upwards(current_tag, selector)
        while current_tag
          found = current_tag.at_css(selector)
          return found if found

          return nil unless current_tag.respond_to?(:parent)

          current_tag = current_tag.parent
        end
      end

      ##
      # Searches for the closest parent that matches the given tag name.
      def find_tag_in_ancestors(current_tag, tag_name)
        return current_tag if current_tag.name == tag_name

        current_tag.ancestors(tag_name).first
      end
    end
  end
end
