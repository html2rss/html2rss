# frozen_string_literal: true

module Html2rss
  module RssBuilder
    ##
    # Builds the <channel> tag (with the provided maker).
    class Channel
      ##
      # @return nil
      def self.add(channel_maker, config, attributes)
        attributes.each do |attribute_name|
          channel_maker.public_send("#{attribute_name}=", config.public_send(attribute_name))
        end

        channel_maker.generator = "html2rss V. #{::Html2rss::VERSION}"
        channel_maker.lastBuildDate = Time.now
      end
    end
  end
end
