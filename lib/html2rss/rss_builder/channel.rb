# frozen_string_literal: true

module Html2rss
  module RssBuilder
    ##
    # Builds the <channel> tag (with the provided maker).
    class Channel
      ##
      # @param maker [RSS::Maker::RSS20::Channel]
      # @param config [Html2rss::Config]
      # @param tags [Set<Symbol>]
      # @return nil
      def self.add(maker, config, tags)
        tags.each { |tag| maker.public_send(:"#{tag}=", config.public_send(tag)) }

        maker.generator = "html2rss V. #{::Html2rss::VERSION}"
        maker.lastBuildDate = Time.now
      end
    end
  end
end
