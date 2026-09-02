# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Facade over a backend-native HTML document.
    #
    # Domain code type-checks and parses through this class; only
    # {Backend} (and Sanitize transformers) touch raw parser types.
    class Document
      ##
      # @param html [String] HTML markup
      # @param backend [Module] parser adapter (default {Backend.current})
      # @param strip_comments [Boolean] remove HTML comments after parse
      # @return [Document]
      def self.parse(html, backend: Backend.current, strip_comments: true)
        native = backend.parse(html)
        backend.remove_comments!(native) if strip_comments
        wrap(native, backend:)
      end

      ##
      # @param html [String] HTML fragment markup
      # @param backend [Module]
      # @return [Object] backend-native fragment (duck-typed node)
      def self.fragment(html, backend: Backend.current)
        backend.fragment(html)
      end

      ##
      # @param native [Object, Document] backend document or existing facade
      # @param backend [Module]
      # @return [Document]
      def self.wrap(native, backend: Backend.current)
        return native if native.is_a?(self)

        new(native, backend:)
      end

      ##
      # Duck-typed HTML document predicate (facade or either known backend native).
      #
      # @param obj [Object]
      # @return [Boolean]
      def self.html_document?(obj)
        return true if obj.is_a?(self)
        return true if obj.respond_to?(:html_document?) && obj.html_document?
        return true if Backend::Nokogiri.html_document?(obj)
        return true if Backend::Rust.html_document?(obj)

        Backend::Nokolexbor.html_document?(obj)
      rescue LoadError
        false
      end

      ##
      # @param native [Object] backend-native document
      # @param backend [Module]
      def initialize(native, backend: Backend.current)
        @native = native
        @backend = backend
      end

      # @return [Object] backend-native document
      attr_reader :native

      # @return [Module] parser adapter that produced {#native}
      attr_reader :backend

      # @return [Boolean]
      def html_document? = true

      # @return [Symbol]
      def backend_name = @backend.name

      ##
      # @param selector [String]
      # @return [Object]
      def css(selector, ...)
        @native.css(Html2rss::Html::Css.normalize(selector, backend: @backend), ...)
      end

      ##
      # @param selector [String]
      # @return [Object, nil]
      def at_css(selector, ...)
        @native.at_css(Html2rss::Html::Css.normalize(selector, backend: @backend), ...)
      end

      ##
      # @return [Document] frozen facade (native frozen when supported)
      def freeze
        @native.freeze if @native.respond_to?(:freeze)
        super
      end

      def method_missing(method_name, ...)
        return super unless @native.respond_to?(method_name)

        @native.public_send(method_name, ...)
      end

      # @param method_name [Symbol]
      # @param include_private [Boolean]
      # @return [Boolean]
      def respond_to_missing?(method_name, include_private = false)
        @native.respond_to?(method_name, include_private) || super
      end
    end
  end
end
