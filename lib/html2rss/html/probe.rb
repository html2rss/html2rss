# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Case-insensitive DOM wire matching for MIME types, tag names, and link relations.
    module Probe
      APPLICATION_LD_JSON = 'application/ld+json'
      APPLICATION_JSON = 'application/json'
      APPLICATION_JSON_OEMBED = 'application/json+oembed'
      APPLICATION_RSS_XML = 'application/rss+xml'
      APPLICATION_ATOM_XML = 'application/atom+xml'

      FOLDED_APPLICATION_LD_JSON = APPLICATION_LD_JSON.freeze
      FOLDED_APPLICATION_JSON = APPLICATION_JSON.freeze
      FOLDED_APPLICATION_JSON_OEMBED = APPLICATION_JSON_OEMBED.freeze
      FOLDED_APPLICATION_RSS_XML = APPLICATION_RSS_XML.freeze
      FOLDED_APPLICATION_ATOM_XML = APPLICATION_ATOM_XML.freeze

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
        fold(node.name)
      end

      ##
      # @param type [String, Symbol, #to_s, nil] MIME type attribute value
      # @return [String] media type without parameters, folded
      def mime_base(type)
        fold(type.to_s.split(';', 2).first.to_s.strip)
      end

      ##
      # @param actual [String, Symbol, #to_s, nil] observed MIME type
      # @param expected [Array<String>] canonical MIME types to match
      # @return [Boolean]
      def mime_match?(actual, *expected)
        base = mime_base(actual)
        expected.any? { |candidate| base == mime_base(candidate) }
      end

      ##
      # @param doc [Nokogiri::XML::Node]
      # @param mime_types [Array<String>] optional MIME filters (folded once per call)
      # @return [Array<Nokogiri::XML::Element>]
      def scripts(doc, *mime_types)
        folded = mime_types.map { |mime| mime_base(mime) }.freeze unless mime_types.empty?

        doc.css('script').reject do |script|
          folded && !folded.include?(mime_base(script['type']))
        end
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
