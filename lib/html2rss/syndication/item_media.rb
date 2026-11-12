# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Reads the media files and image a feed item declares, for {Parser}: the +rss+ library parses the
    # item text but drops Media RSS, so this module reads the same document's item elements.
    #
    # Enclosures, in document order and once per URL: RSS 2.0 +enclosure+ (+url+, +type+, +length+),
    # Atom +link rel="enclosure"+ (+href+, +type+, +length+) and Media RSS +media:content+, also inside
    # +media:group+ (+url+, +type+, +fileSize+, +duration+). An item +itunes:duration+ is the duration of
    # every enclosure that declares none. A file declaring an audio or video +medium+ that is no media file
    # and has no file extension is a watch or player page and no enclosure. The item image is its
    # +itunes:image+, else its first +media:thumbnail+ (also inside +media:group+), else its first image
    # file (+medium="image"+ or an image type). Sizes, durations and kinds come from {Article::Enclosure}.
    module ItemMedia
      # Namespace prefixes the item queries bind.
      NAMESPACES = {
        'atom' => 'http://www.w3.org/2005/Atom',
        'media' => 'http://search.yahoo.com/mrss/',
        'itunes' => 'http://www.itunes.com/dtds/podcast-1.0.dtd'
      }.freeze
      # Item elements in document order: RSS 2.0 +rss/channel/item+, RSS 1.0 +rdf:RDF/item+, Atom +feed/entry+.
      ITEMS = "/*/*[local-name()='item' or local-name()='entry'] | /*/*/*[local-name()='item']"
      # Enclosure elements of one item, in document order.
      ENCLOSURES = "enclosure | atom:link[@rel='enclosure'] | media:content | media:group/media:content"
      # Thumbnail URLs of one item, in document order (blank ones skipped, like a blank iTunes image).
      THUMBNAILS = 'media:thumbnail/@url[normalize-space()] | media:group/media:thumbnail/@url[normalize-space()]'
      # The item's iTunes image URL.
      ITUNES_IMAGE = 'itunes:image/@href[normalize-space()]'
      # Media RSS +medium+ values of a playable file; such an entry that is no media file is a player page.
      PLAYABLE_MEDIUMS = %w[audio video].freeze

      class << self
        ##
        # @param body [String] the feed document
        # @param count [Integer] items the +rss+ library read from +body+
        # @yieldparam raw [String, nil] a declared URL
        # @yieldreturn [Html2rss::Url, nil] that URL made absolute, or nil when unusable
        # @return [Array<Hash{Symbol => Object}>] per item, in document order, its +enclosures+ and +image+
        #   when present; all empty when the document's item elements do not number +count+
        def for_items(body, count:, &)
          nodes = Nokogiri::XML(body).xpath(ITEMS)
          return Array.new(count) { {} } unless nodes.size == count

          nodes.map { |node| item_media(node, &) }
        end

        private

        def item_media(node, &resolve)
          duration = node.at_xpath('itunes:duration', NAMESPACES)&.text
          files = node.xpath(ENCLOSURES, NAMESPACES).filter_map { file(_1, &resolve) }
          enclosures = files.map { |element, enclosure| facts(element, enclosure, duration) }
          { enclosures: enclosures.uniq { _1[:url].to_s }, image: image(node, files, &resolve) }
            .reject { |_, value| value.nil? || value == [] }
        end

        # @return [Array(Nokogiri::XML::Element, Article::Enclosure), nil] the element and its file;
        #   nil without a URL or for a watch or player page
        def file(element)
          return unless (url = yield(attribute(element, 'url', 'href')))

          enclosure = Article::Enclosure.new(url:, type: attribute(element, 'type'))
          [element, enclosure] unless player_page?(element, enclosure)
        end

        def player_page?(element, enclosure)
          PLAYABLE_MEDIUMS.include?(element['medium']) && !enclosure.media? && !enclosure.file_extension?
        end

        def facts(element, enclosure, item_duration)
          { url: enclosure.url, type: attribute(element, 'type'),
            bytes_length: Article::Enclosure.parse_size(attribute(element, 'length', 'fileSize')),
            duration: Article::Enclosure.parse_duration(attribute(element, 'duration') || item_duration) }.compact
        end

        def image(node, files)
          declared = node.at_xpath(ITUNES_IMAGE, NAMESPACES) || node.at_xpath(THUMBNAILS, NAMESPACES)
          (declared && yield(declared.value)) || first_image_file(files)
        end

        def first_image_file(files)
          files.find { |element, enclosure| element['medium'] == 'image' || enclosure.image? }&.last&.url
        end

        def attribute(element, *names)
          names.filter_map { element[_1]&.strip }.find { !_1.empty? }
        end
      end
    end
  end
end
