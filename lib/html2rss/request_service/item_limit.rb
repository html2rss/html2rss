# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class RequestService
    ##
    # Decides while a feed streams in whether enough items have arrived to stop downloading, and repairs
    # the truncated document so {Syndication::Parser} sees well-formed XML.
    #
    # Completed +item+/+entry+ end-elements are counted with a SAX push parser. The target is
    # {HEADROOM} times the caller's limit: deduplication and the parser's skipping of URL-less items run
    # after the cut and must still leave +limit+ articles in the usual case. Channel metadata an Atom feed
    # places after its entries is lost on an early stop.
    class ItemLimit
      # Element names that close one feed item (RSS/RDF +item+, Atom +entry+).
      ITEM_NAMES = %w[item entry].freeze
      # Items read per requested item, so dedup and skipped items cannot leave the result short.
      HEADROOM = 2

      # SAX handler counting completed items.
      class Counter < Nokogiri::XML::SAX::Document
        # @return [Integer] completed items so far
        def items = @items ||= 0

        # @param name [String] local element name
        # @param _prefix [String, nil] namespace prefix (unused)
        # @param _uri [String, nil] namespace URI (unused)
        # @return [void]
        def end_element_namespace(name, _prefix, _uri)
          @items = items + 1 if ITEM_NAMES.include?(name)
        end
      end

      ##
      # @param body [String] a feed document cut off after an item
      # @return [String] well-formed XML with the open elements closed
      def self.repair(body)
        Nokogiri::XML(body).to_xml # libxml's default parse recovers from a truncated tail
      end

      ##
      # @param limit [Integer] items the caller keeps
      def initialize(limit)
        @target = limit * HEADROOM
        @counter = Counter.new
        @parser = Nokogiri::XML::SAX::PushParser.new(@counter)
      end

      ##
      # Feeds the next bytes of the document.
      #
      # @param bytes [String] the next part of the feed body
      # @return [Boolean] whether enough items are complete; false (and for good: libxml refuses further input
      #   after an error) once the XML is malformed, so the caller falls back to reading the whole body
      def reached?(bytes)
        @parser << bytes
        @counter.items >= @target
      rescue Nokogiri::XML::SyntaxError
        false
      end
    end
  end
end
