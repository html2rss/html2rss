# frozen_string_literal: true

require 'sanitize'

module Html2rss
  module AttributePostProcessors
    ##
    # Returns sanitized HTML code as String.
    #
    # It sanitizes by using the [sanitize gem](https://github.com/rgrove/sanitize) with
    # [Sanitize::Config::RELAXED](https://github.com/rgrove/sanitize#sanitizeconfigrelaxed).
    #
    # Furthermore, it adds:
    #
    # - `rel="nofollow noopener noreferrer"` to <a> tags
    # - `referrer-policy='no-referrer'` to <img> tags
    # - wraps all <img> tags, whose direct parent is not an <a>, into an <a>
    #   linking to the <img>'s `src`.
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
    #        selector: '.section'
    #        extractor: html
    #        post_process:
    #          name: sanitize_html
    #
    # Would return:
    #    '<p>Lorem <b>ipsum</b> dolor ...</p>'
    class SanitizeHtml
      URL_ELEMENTS_WITH_URL_ATTRIBUTE = { 'a' => :href, 'img' => :src }.freeze
      private_constant :URL_ELEMENTS_WITH_URL_ATTRIBUTE

      ##
      # @param value [String]
      # @param env [Item::Context]
      def initialize(value, env)
        @value = value
        @channel_url = env[:config].url
      end

      ##
      # @return [String]
      def get
        Sanitize.fragment(@value, sanitize_config).to_s.split.join(' ')
      end

      private

      ##
      # @return [Sanitize::Config]
      def sanitize_config
        Sanitize::Config.merge(
          Sanitize::Config::RELAXED,
          attributes: { all: %w[dir lang alt title translate] },
          add_attributes: {
            'a' => { 'rel' => 'nofollow noopener noreferrer', 'target' => '_blank' },
            'img' => { 'referrer-policy' => 'no-referrer' }
          },
          transformers: [transform_urls_to_absolute_ones, WRAP_IMG_IN_A]
        )
      end

      ##
      # @return [Proc]
      def transform_urls_to_absolute_ones
        lambda do |env|
          return unless URL_ELEMENTS_WITH_URL_ATTRIBUTE.key?(env[:node_name])

          url_attribute = URL_ELEMENTS_WITH_URL_ATTRIBUTE[env[:node_name]]
          url = env[:node][url_attribute]

          env[:node][url_attribute] = Html2rss::Utils.build_absolute_url_from_relative(url, @channel_url)
        end
      end

      ##
      # Wraps an <img> tag into an <a> tag which links to `img.src`.
      WRAP_IMG_IN_A = lambda do |env|
        return if env[:node_name] != 'img'

        img = env[:node]

        return if img.parent.name == 'a'

        anchor = Nokogiri::XML::Node.new('a', img)
        anchor[:href] = img[:src]

        anchor.add_child img.dup

        img.replace(anchor)
      end
    end
  end
end
