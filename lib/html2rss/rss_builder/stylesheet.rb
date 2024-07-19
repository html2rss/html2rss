# frozen_string_literal: true

module Html2rss
  module RssBuilder
    ##
    # Adds XML stylesheet tags (with the provided maker).
    class Stylesheet
      ##
      # Adds the stylesheet XML tags to the RSS.
      #
      # @param maker [RSS::Maker::RSS20] RSS maker object.
      # @param stylesheets [Array<Html2rss::Config::Stylesheet>] Array of stylesheet configurations.
      # @return [nil]
      def self.add(maker, stylesheets)
        stylesheets.each do |stylesheet|
          add_stylesheet(maker, stylesheet)
        end
      end

      ##
      # Adds a single Stylesheet to the RSS.
      #
      # @param maker [RSS::Maker::RSS20] RSS maker object.
      # @param stylesheet [Html2rss::Config::Stylesheet] Stylesheet configuration.
      # @return [nil]
      def self.add_stylesheet(maker, stylesheet)
        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          xss.href = stylesheet.href
          xss.type = stylesheet.type
          xss.media = stylesheet.media
        end
      end

      private_class_method :add_stylesheet
    end
  end
end
