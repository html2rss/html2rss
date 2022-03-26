# frozen_string_literal: true

module Html2rss
  module RssBuilder
    ##
    # Adds XML stylesheet tags (with the provided maker).
    class Stylesheet
      ##
      # Adds the stylesheet xml tags to the RSS.
      #
      # @param stylesheets [Array<Hash>]
      # @param maker [RSS::Maker::RSS20]
      # @return nil
      def self.add(maker, stylesheets)
        stylesheets.each do |stylesheet|
          maker.xml_stylesheets.new_xml_stylesheet do |xss|
            xss.href = stylesheet[:href]
            xss.type = stylesheet[:type]
            xss.media = stylesheet[:media]
          end
        end
      end
    end
  end
end
