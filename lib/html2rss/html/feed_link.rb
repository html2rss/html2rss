# frozen_string_literal: true

module Html2rss
  module Html
    # A native RSS/Atom hint from a document head +link[rel=alternate]+.
    #
    # Does not guess +/feed+ or +/rss.xml+ paths — that stays in configs +probe_rss+.
    FeedLink = Data.define(:href, :mime_type) do
      class << self
        ##
        # Collects RSS/Atom +rel=alternate+ links from +doc+'s +head+.
        #
        # @param doc [Nokogiri::XML::Node] parsed HTML document
        # @return [Array<FeedLink>] native feed hints, omitting blanks and non-feed types
        def from_document(doc)
          doc.css('head link[rel~="alternate"][href]').filter_map { |node| from_node(node) }
        end

        private

        def from_node(node)
          href = node['href']&.strip
          mime_type = feed_mime_type(node['type'])
          new(href:, mime_type:) unless href.nil? || href.empty? || mime_type.nil?
        end

        def feed_mime_type(type)
          media_type = type.to_s.split(';', 2).first.strip.downcase
          media_type if media_type in 'application/rss+xml' | 'application/atom+xml'
        end
      end
    end
  end
end
