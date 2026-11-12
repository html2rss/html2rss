# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Reads the media files and image a feed item declares, for {Parser}: the +rss+ library parses the
    # item text but drops Media RSS, so this module reads the same document's item elements.
    #
    # Enclosures, in document order and once per URL: RSS 2.0 +enclosure+ (+url+, +type+, +length+),
    # Atom +link rel="enclosure"+ (+href+, +type+, +length+) and Media RSS +media:content+, also inside
    # +media:group+ (+url+, +type+, +fileSize+, +duration+). A Media RSS +medium+ is a kind hint, never a
    # drop signal: +audio+ or +video+ is the file's kind, typing an untyped file
    # ({Article::Enclosure::KIND_TYPES}), and +image+ keeps an untyped file an image. A watch or player
    # page ({Article::Enclosure#player_page?}) that is not declared an image is
    # no enclosure. An item +itunes:duration+ is the duration of every audio or video file that declares
    # none. The item image is its +itunes:image+ (+href+, or the URL as its text), else its first
    # +media:thumbnail+ (also inside +media:group+), else its first image file when only +medium="image"+
    # marks it (a file typed as an image becomes the item image through {Article}). Sizes, durations and
    # kinds come from {Article::Enclosure}. Items match by namespace
    # ({ITEMS}); a document without any media marker ({MEDIA_MARKERS}) is not parsed a second time.
    module ItemMedia
      # Namespace prefixes the item queries bind.
      NAMESPACES = {
        'rss1' => 'http://purl.org/rss/1.0/',
        'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        'atom' => 'http://www.w3.org/2005/Atom',
        'media' => 'http://search.yahoo.com/mrss/',
        'itunes' => 'http://www.itunes.com/dtds/podcast-1.0.dtd'
      }.freeze
      # Item elements in document order, by format: RSS 2.0 +item+ (no namespace) under +rss/channel+,
      # RSS 1.0 +item+ under +rdf:RDF+, Atom +entry+ under +feed+. Extension elements named +item+ never count.
      ITEMS = '/rss/channel/item | /rdf:RDF/rss1:item | /atom:feed/atom:entry'
      # Text only a document declaring item media contains: an RSS 2.0 enclosure, an Atom enclosure link,
      # or the Media RSS or iTunes namespace. Any other document is not parsed a second time.
      MEDIA_MARKERS = Regexp.union('<enclosure', /rel=["']enclosure["']/, NAMESPACES['media'], NAMESPACES['itunes'])
      # Enclosure elements of one item, in document order.
      ENCLOSURES = "enclosure | atom:link[@rel='enclosure'] | media:content | media:group/media:content"
      # Thumbnail URLs of one item, in document order (blank ones skipped, like a blank iTunes image).
      THUMBNAILS = 'media:thumbnail/@url[normalize-space()] | media:group/media:thumbnail/@url[normalize-space()]'
      # The item's iTunes image URL: its +href+, else the URL written as the element text.
      ITUNES_IMAGE = 'itunes:image/@href[normalize-space()] | ' \
                     'itunes:image[not(normalize-space(@href))][normalize-space()]'

      class << self
        ##
        # @param body [String] the feed document
        # @param count [Integer] items the +rss+ library read from +body+
        # @param url [String, Html2rss::Url, nil] the feed URL, for the log when items cannot be matched
        # @yieldparam raw [String, nil] a declared URL, possibly padded with whitespace
        # @yieldreturn [Html2rss::Url, nil] that URL made absolute, or nil when unusable
        # @return [Array<Hash{Symbol => Object}>] per item, in document order, its +enclosures+ and +image+
        #   when present; all empty when the document declares no media or its item elements do not
        #   number +count+ (logged)
        def for_items(body, count:, url: nil, &)
          return Array.new(count) { {} } unless MEDIA_MARKERS.match?(body)

          nodes = Nokogiri::XML(body).xpath(ITEMS, NAMESPACES)
          return nodes.map { |node| item_media(node, &) } if nodes.size == count

          warn_mismatch(nodes.size, count, url)
          Array.new(count) { {} }
        end

        private

        def item_media(node, &resolve)
          duration = Article::Enclosure.parse_duration(node.at_xpath('itunes:duration', NAMESPACES)&.text)
          files = node.xpath(ENCLOSURES, NAMESPACES).filter_map { file(_1, duration, &resolve) }
          { enclosures: files.map(&:first).uniq { _1[:url].to_s }, image: image(node, files, &resolve) }
            .reject { |_, value| value.nil? || value == [] }
        end

        # @return [Array(Hash{Symbol => Object}, Boolean), nil] the file's facts and whether it is an image;
        #   nil without a URL or for a watch or player page
        def file(element, item_duration)
          return unless (url = yield(attribute(element, 'url', 'href')))

          bytes_length = Article::Enclosure.parse_size(attribute(element, 'length', 'fileSize'))
          enclosure = Article::Enclosure.new(url:, type: attribute(element, 'type'), bytes_length:)
          image = element['medium'] == 'image' || enclosure.image?
          return if enclosure.player_page? && !image

          [facts(element, enclosure, item_duration), image]
        end

        # The file's facts: its declared type and its +medium+ as kind (+audio+, +video+), which types an
        # untyped file; its own duration, else the item's when it is audio or video.
        def facts(element, enclosure, item_duration)
          kind = Article::Enclosure::KIND_TYPES.each_key.find { _1.name == element['medium'] }
          file = Article::Enclosure.new(url: enclosure.url, type: attribute(element, 'type'), kind:)
          duration = Article::Enclosure.parse_duration(attribute(element, 'duration'))
          { url: file.url, type: attribute(element, 'type'), kind:, bytes_length: enclosure.bytes_length.nonzero?,
            duration: duration || (item_duration if file.media?) }.compact
        end

        def image(node, files)
          declared = node.at_xpath(ITUNES_IMAGE, NAMESPACES) || node.at_xpath(THUMBNAILS, NAMESPACES)
          (declared && yield(declared.content)) || hinted_image(files.find { |_facts, image| image }&.first)
        end

        # The first image file when only its +medium="image"+ makes it one; a file typed as an image becomes
        # the item image through {Article#initialize}, the owner of that fallback.
        def hinted_image(facts)
          return unless facts

          file = Article::Enclosure.new(**facts)
          file.url unless file.image?
        end

        def attribute(element, *names)
          names.filter_map { element[_1]&.strip }.find { !_1.empty? }
        end

        def warn_mismatch(elements, count, url)
          Log.warn({
            event_name: 'syndication.item_media_mismatch', feed_url: url,
            message: "Syndication::ItemMedia: #{elements} item elements for #{count} parsed items; no item media read"
          }.to_json)
        end
      end
    end
  end
end
