require 'faraday'
require 'open-uri'
require 'nokogiri'
require_relative 'item_extractor'

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

      post_process(method_name, value)
    end

    def post_process(method_name, value)
      case method_name
      when :link
        URI(value)
      when :updated
        Time.parse(value).to_s
      else
        value
      end
    end

    def self.from_url(url, config)
      connection = Faraday.new(url: url, headers: config.headers)
      page = Nokogiri::HTML(connection.get.body)
      page.css(config.selector('items')).map { |xml_item|
        new xml_item, config
      }
    end
  end
end
