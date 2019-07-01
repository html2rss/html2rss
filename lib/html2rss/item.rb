require 'faraday'
require 'faraday_middleware'
require 'open-uri'
require 'nokogiri'
require_relative 'item_extractors'
require_relative 'attribute_post_processors'

module Html2rss
  class Item
    def initialize(xml, config)
      @xml = xml
      @config = config
    end

    def respond_to_missing?(method_name, _include_private = false)
      config.attribute_names.include?(method_name) || super
    end

    def method_missing(method_name, *_args)
      attribute_config = config.options(method_name.to_s)
      return super unless attribute_config

      extractor = ItemExtractors.get_extractor(attribute_config.fetch('extractor', ItemExtractors::DEFAULT))
      value = extractor.new(xml, attribute_config).get

      post_process(value, attribute_config.fetch('post_process', false))
    end

    def available_attributes
      @available_attributes ||= (%w[title link description author comments updated] &
        @config.attribute_names) - ['categories']
    end

    def valid?
      [title.to_s, description.to_s].join('') != ''
    end

    def categories
      config.categories.map(&method(:method_missing)).uniq.keep_if { |category| category.to_s != '' }
    end

    ##
    # Returns an array of Item.
    def self.from_url(url, config)
      connection = Faraday.new(url: url, headers: config.headers) { |faraday|
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter Faraday.default_adapter
      }

      page = Nokogiri::HTML(connection.get.body)
      page.css(config.selector('items')).map do |xml_item|
        new xml_item, config
      end
    end

    private

    attr_reader :xml, :config

    def post_process(value, post_process_options)
      return value unless post_process_options

      post_process_options = [post_process_options] unless post_process_options.is_a?(Array)

      post_process_options.each do |options|
        value = AttributePostProcessors.get_processor(options)
                                       .new(value, options, self)
                                       .get
      end

      value
    end
  end
end
