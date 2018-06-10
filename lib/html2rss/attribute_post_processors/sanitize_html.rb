require 'sanitize'

module Html2rss
  module AttributePostProcessors
    class SanitizeHtml
      def initialize(value, _options, _item)
        @value = value
      end

      def get
        Sanitize.fragment(@value, Sanitize::Config.merge(
                                    Sanitize::Config::RELAXED,
                                    add_attributes: {
                                      'a' => { 'rel' => 'nofollow noopener noreferrer' }
                                    }
        ))
      end
    end
  end
end
