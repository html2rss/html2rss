# frozen_string_literal: true

require 'cgi'
require 'json'

module Html2rss
  ##
  # A naive implementation of "Object to XML": converts a Ruby object to XML format.
  class ObjectToXmlConverter
    OBJECT_TO_XML_TAGS = {
      hash: ['<object>', '</object>'],
      enumerable: ['<array>', '</array>']
    }.freeze

    ##
    # @param object [Object] any Ruby object (Hash, Array, String, Symbol, etc.)
    def initialize(object)
      @object = object
    end

    ##
    # Converts the object to XML format.
    #
    # @return [String] representing the object in XML
    def call
      object_to_xml(@object)
    end

    private

    def object_to_xml(object)
      case object
      when Hash
        hash_to_xml(object)
      when Enumerable
        enumerable_to_xml(object)
      else
        CGI.escapeHTML(object.to_s)
      end
    end

    def hash_to_xml(object)
      prefix, suffix = OBJECT_TO_XML_TAGS[:hash]
      inner_xml = object.map { |key, value| "<#{key}>#{object_to_xml(value)}</#{key}>" }.join

      "#{prefix}#{inner_xml}#{suffix}"
    end

    def enumerable_to_xml(object)
      prefix, suffix = OBJECT_TO_XML_TAGS[:enumerable]
      inner_xml = object.map { |value| object_to_xml(value) }.join

      "#{prefix}#{inner_xml}#{suffix}"
    end
  end
end
