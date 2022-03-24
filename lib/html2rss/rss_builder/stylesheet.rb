# frozen_string_literal: true

module Html2rss
  module RssBuilder
    class Stylesheet
      ##
      # Adds the xml stylesheets to the RSS::Maker.
      #
      # @param stylesheet [Array<Hash>] <description>
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
