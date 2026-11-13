# frozen_string_literal: true

module Html2rss
  module Html
    FeedLink = Data.define(:href, :mime_type, :title)

    # A native RSS/Atom/RDF hint from a document head +link[rel=alternate]+.
    #
    # Does not guess +/feed+ or +/rss.xml+ paths — that stays in configs +probe_rss+.
    # +title+ is the link's stripped +title+ attribute (empty when absent).
    class FeedLink
      class << self
        ##
        # Collects RSS/Atom/RDF +rel=alternate+ links from +doc+'s +head+.
        #
        # @param doc [Nokogiri::XML::Node] parsed HTML document
        # @return [Array<FeedLink>] native feed hints, omitting blanks and non-feed types
        def from_document(doc)
          doc.css('head link[rel~="alternate"][href]').filter_map { |node| from_node(node) }
        end

        private

        def from_node(node)
          href = node['href'].strip # the head selector guarantees an href attribute
          mime_type = feed_mime_type(node['type'])
          new(href:, mime_type:, title: node['title'].to_s.strip) unless href.empty? || mime_type.nil?
        end

        def feed_mime_type(type)
          Probe::FEED_MIME_TYPES.find { |mime| Probe.mime_match?(type, mime) }
        end
      end
    end
  end
end
