# frozen_string_literal: true

module Html2rss
  module Html
    module Backend
      ##
      # Optional Rust HTML adapter via +html2rss_parser+ (experiment only).
      #
      # Loaded lazily after +bundle exec rake compile+. XML / sitemap paths must
      # stay on Nokogiri — see {Sitemap}.
      module Rust
        ##
        # Minimal NodeSet duck: Nokogiri NodeSet responds to +#text+; plain Arrays do not.
        class NodeSet
          include Enumerable

          # @param nodes [Array]
          def initialize(nodes)
            @nodes = Array(nodes)
          end

          # @return [Array]
          attr_reader :nodes

          # @yieldparam node [Object]
          # @return [Enumerator, self]
          def each(&)
            return enum_for(:each) unless block_given?

            @nodes.each(&)
            self
          end

          # @return [Integer]
          def size = @nodes.size
          alias length size

          # @return [Boolean]
          def empty? = @nodes.empty?

          # @param index [Integer]
          # @return [Object, nil]
          def [](index) = @nodes[index]

          # @return [Object, nil]
          def first = @nodes.first

          # @return [Object, nil]
          def last = @nodes.last

          # @return [Array]
          def to_a = @nodes.dup

          # Concatenate visible text like Nokogiri::XML::NodeSet#text.
          #
          # @return [String]
          def text
            @nodes.map { |node| node.respond_to?(:text) ? node.text : '' }.join
          end

          # Nokogiri NodeSet#attr reads from the first node.
          #
          # @param name [String, Symbol]
          # @return [String, nil]
          def attr(name)
            node = @nodes.first
            return unless node

            if node.respond_to?(:attr)
              node.attr(name)
            elsif node.respond_to?(:[])
              node[name.to_s]
            end
          end

          # @param key [Integer, String, Symbol]
          # @return [Object, nil]
          def [](key)
            case key
            when Integer then @nodes[key]
            else attr(key)
            end
          end

          # @param selector [String]
          # @return [NodeSet]
          def css(selector, ...)
            NodeSet.new(@nodes.flat_map { |node| Array(node.css(selector, ...)) })
          end

          # @param selector [String]
          # @return [Object, nil]
          def at_css(selector, ...)
            @nodes.lazy.filter_map { |node| node.at_css(selector, ...) }.first
          end
        end

        module_function

        # @return [Symbol]
        def name = :rust

        ##
        # @param html [String]
        # @return [Object] native document
        def parse(html)
          engine::Document.parse(html)
        end

        ##
        # @param html [String]
        # @return [Object] document fragment
        def fragment(html)
          engine::Document.fragment(html)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def html_document?(obj)
          obj.is_a?(engine::Document) || (obj.respond_to?(:html_document?) && obj.html_document?)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node?(obj)
          obj.is_a?(engine::Document) || obj.is_a?(engine::Node)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node_set?(obj)
          obj.is_a?(NodeSet) || (obj.is_a?(Array) && obj.all? { |item| node?(item) })
        end

        ##
        # Wrap Array CSS results so extractors can call +#text+.
        #
        # @param nodes [Object]
        # @return [NodeSet, Object]
        def wrap_nodeset(nodes)
          nodes.is_a?(Array) ? NodeSet.new(nodes) : nodes
        end

        ##
        # @param doc [Object]
        # @return [void]
        def remove_comments!(doc)
          if doc.respond_to?(:remove_comments!)
            doc.remove_comments!
            return
          end

          doc.traverse do |node|
            node.remove if node.respond_to?(:comment?) && node.comment?
          end
        end

        ##
        # @return [Class]
        def syntax_error_class
          Html2rss::Html::NativeEngine::SyntaxError
        end

        def engine
          Html2rss::Html::NativeEngine.load!
          Html2rss::Html::NativeEngine
        end
        module_function :engine
      end
    end
  end
end
