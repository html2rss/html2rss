module Html2rss
  module ItemExtractor
    TEXT = proc { |xml, options| xml.css(options['selector'])&.text }
    ATTRIBUTE = proc { |xml, options| xml.css(options['selector']).attr(options['attribute']).to_s }

    HREF = proc { |xml, options|
      uri = URI(options['channel']['url'])
      uri.path = xml.css(options['selector']).attr('href')
      uri
    }

    HTML = proc { |xml, options| xml.css(options['selector']).to_s }
  end
end
