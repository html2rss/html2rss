# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Backend-agnostic predicates for HTML/XML nodes returned from CSS queries.
    #
    # Nodes stay backend-native for allocation locality; this module is the
    # type-check surface that replaces +is_a?(Nokogiri::XML::Node)+ gates.
    module Node
      module_function

      ##
      # @param obj [Object]
      # @return [Boolean]
      def node?(obj)
        return true if obj.is_a?(Document)
        return true if Backend::Nokogiri.node?(obj)

        Backend::Nokolexbor.node?(obj)
      rescue LoadError
        false
      end

      ##
      # @param obj [Object]
      # @return [Boolean]
      def node_set?(obj)
        return true if Backend::Nokogiri.node_set?(obj)

        Backend::Nokolexbor.node_set?(obj)
      rescue LoadError
        false
      end

      ##
      # @param obj [Object, Document, nil]
      # @return [Object, nil] backend-native node
      def unwrap(obj)
        obj.is_a?(Document) ? obj.native : obj
      end
    end
  end
end
