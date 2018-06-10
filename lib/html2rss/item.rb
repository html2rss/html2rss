require 'faraday'
require 'open-uri'
require 'nokogiri'
require_relative 'item_extractor'
require_relative 'attribute_post_processors'

module Html2rss
  class Item
    attr_reader :xml, :config

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

      extractor = attribute_config['extractor'] || 'text'
      proc = ItemExtractor.const_get extractor.upcase.to_sym
      value = proc.call(xml, attribute_config)

      post_process_options = attribute_config.fetch('post_process', false)
      value = post_process(value, post_process_options) if post_process_options

      value
    end

    def self.from_url(url, config)
      connection = Faraday.new(url: url, headers: config.headers)
      page = Nokogiri::HTML(connection.get.body)
      page.css(config.selector('items')).map { |xml_item|
        new xml_item, config
      }
    end

    private

    def post_process(value, options)
      Html2rss::AttributePostProcessors.get_processor(options)
                                       .new(value, options, self)
                                       .get
    end
  end
end
