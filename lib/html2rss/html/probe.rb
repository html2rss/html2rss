# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Case-insensitive DOM wire matching for MIME types, tag names, and link relations.
    module Probe
      # Canonical MIME type strings for script and alternate link matching.
      APPLICATION_LD_JSON = 'application/ld+json'
      # @see #mime_match?
      APPLICATION_JSON = 'application/json'
      # @see #mime_match?
      APPLICATION_JSON_OEMBED = 'application/json+oembed'
      # @see #mime_match?
      APPLICATION_RSS_XML = 'application/rss+xml'
      # @see #mime_match?
      APPLICATION_ATOM_XML = 'application/atom+xml'

      module_function

      ##
      # @param string [String, Symbol, #to_s] wire value
      # @return [String] folded comparison key
      def fold(string)
        string.to_s.downcase
      end

      ##
      # @param node [Nokogiri::XML::Node]
      # @return [String] folded element name
      def tag(node)
        name = node.name
        return fold(name) unless name.is_a?(String)
        return name if name.ascii_only? && !name.match?(/[A-Z]/)

        fold(name)
      end

      ##
      # @param type [String, Symbol, #to_s, nil] MIME type attribute value
      # @return [String] media type without parameters, folded
      def mime_base(type)
        raw = type.to_s
        return fold(raw) unless raw.include?(';') || raw.match?(/\A\s|\s\z/)

        fold(raw.split(';', 2).first.to_s.strip)
      end

      ##
      # @param actual [String, Symbol, #to_s, nil] observed MIME type
      # @param expected [Array<String>] canonical MIME types to match
      # @return [Boolean]
      def mime_match?(actual, *expected)
        base = mime_base(actual)
        expected.any? { |candidate| base == candidate || base == mime_base(candidate) }
      end

      ##
      # @param doc [Nokogiri::XML::Node]
      # @param mime_types [Array<String>] optional MIME filters (folded once per call)
      # @return [Array<Nokogiri::XML::Element>]
      def scripts(doc, *mime_types)
        return doc.css('script') if mime_types.empty?

        allowed = mime_types.to_set { |mime| mime_base(mime) }
        doc.css('script').select { |script| allowed.include?(mime_base(script['type'])) }
      end

      ##
      # @param doc [Nokogiri::XML::Node]
      # @param rel [String] link rel token
      # @param mime [String, nil] optional MIME filter
      # @return [Array<Nokogiri::XML::Element>]
      def alternate_links(doc, rel:, mime: nil)
        nodes = doc.css(%(link[rel~="#{rel}"][href]))
        return nodes if mime.nil?

        nodes.select { |node| mime_match?(node['type'], mime) }
      end
    end
  end
end
