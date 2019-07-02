require 'sanitize'

module Html2rss
  module AttributePostProcessors
    class SanitizeHtml
      ##
      # Returns sanitized HTML code.
      #
      # Imagine this HTML structure:
      #
      #     <section>
      #       Lorem <b>ipsum</b> dolor...
      #       <iframe src="https://evil.corp/miner"></iframe>
      #       <script>alert();</script>
      #     </section>
      #
      # YAML usage example:
      #
      #    selectors:
      #      description:
      #        selector: section
      #        extractor: html
      #        post_process:
      #          name: sanitize_html
      #
      # Would return:
      #    '<p>Lorem <b>ipsum</b> dolor ...</p>'
      def initialize(value, _options, _item)
        @value = value
      end

      ##
      # - uses the {https://github.com/rgrove/sanitize sanitize gem}
      # - uses the config {https://github.com/rgrove/sanitize#sanitizeconfigrelaxed Sanitize::Config::RELAXED}
      # - adds rel="nofollow noopener noreferrer" to a elements
      # - adds target="_blank" to a elements
      # @return [String]
      def get
        Sanitize.fragment(@value, Sanitize::Config.merge(
                                    Sanitize::Config::RELAXED,
                                    add_attributes: {
                                      'a' => {
                                        'rel' => 'nofollow noopener noreferrer',
                                        'target' => '_blank'
                                      }
                                    }
                                  )).to_s.split.join(' ')
      end
    end
  end
end
