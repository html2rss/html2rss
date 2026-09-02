# frozen_string_literal: true

module Html2rss
  module Html
    module Backend
      ##
      # Optional Rust HTML adapter via +html2rss_parser+ (experiment only).
      #
      # Loaded lazily after +bundle exec rake compile+. XML / sitemap paths must
      # stay on Nokogiri — see {Rust.force_nokogiri_xml!}.
      module Rust
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
        # Rust CSS results are Arrays, not NodeSets.
        #
        # @param obj [Object]
        # @return [Boolean]
        def node_set?(obj)
          obj.is_a?(Array) && obj.all? { |item| node?(item) }
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
