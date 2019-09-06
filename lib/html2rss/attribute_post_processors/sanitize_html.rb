require 'sanitize'

module Html2rss
  module AttributePostProcessors
    ##
    # Returns sanitized HTML code as String.
    # Adds
    #
    # - rel="nofollow noopener noreferrer" to a elements
    # - referrer-policy='no-referrer' to img elements
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
    class SanitizeHtml
      def initialize(value, env)
        @value = value
        @channel_url = env[:config].url
      end

      URL_ELEMENTS_WITH_ATTRIBUTE = {
        'a' => :href,
        'img' => :src
      }.freeze

      def transformer
        lambda do |env|
          return unless URL_ELEMENTS_WITH_ATTRIBUTE.key?(env[:node_name])

          url_attribute = URL_ELEMENTS_WITH_ATTRIBUTE[env[:node_name]]
          url = env[:node][url_attribute]

          return if URI(url).absolute?

          absolute_url = Html2rss::ItemExtractors::Href.build_absolute_url_from_relative(url, @channel_url)

          env[:node][url_attribute] = absolute_url
        end
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
                                    attributes: {
                                      all: %w[dir lang alt title translate]
                                    },
                                    add_attributes: {
                                      'a' => {
                                        'rel' => 'nofollow noopener noreferrer',
                                        'target' => '_blank'
                                      },
                                      'img' => {
                                        'referrer-policy' => 'no-referrer'
                                      }
                                    },
                                    transformers: [transformer]
                                  )).to_s.split.join(' ')
      end
    end
  end
end
