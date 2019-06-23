module Html2rss
  module ItemExtractor
    TEXT = proc { |xml, options|
      element(xml, options)&.text&.strip&.split&.join(' ')
    }

    ATTRIBUTE = proc { |xml, options|
      element(xml, options).attr(options['attribute']).to_s
    }

    HREF = proc { |xml, options|
      href = element(xml, options).attr('href').to_s
      path, query = href.split('?')

      if href.start_with?('http')
        uri = URI(href)
      else
        uri = URI(options['channel']['url'])
        uri.path = path.to_s.start_with?('/') ? path : "/#{path}"
        uri.query = query
      end

      uri
    }

    HTML = proc { |xml, options|
      element(xml, options).to_s
    }

    STATIC = proc { |_xml, options| options['static'] }
    CURRENT_TIME = proc { |_xml, _options| Time.new }

    def self.element(xml, options)
      options['selector'] ? xml.css(options['selector']) : xml
    end
  end
end
