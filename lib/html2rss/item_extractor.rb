require 'sanitize'

module Html2rss
  module ItemExtractor
    TEXT = proc { |xml, options| xml.css(options['selector'])&.text }
    ATTRIBUTE = proc { |xml, options| xml.css(options['selector']).attr(options['attribute']) }

    HREF = proc { |xml, options|
      uri = URI(options['channel']['url'])
      uri.path = xml.css(options['selector']).attr('href')
      uri
    }

    HTML = proc { |xml, options|
      html = xml.css(options['selector']).to_s

      Sanitize.fragment(html, Sanitize::Config.merge(
                                Sanitize::Config::RELAXED,
                                add_attributes: {
                                  'a' => { 'rel' => 'nofollow noopener noreferrer' }
                                }
      ))
    }
  end
end
