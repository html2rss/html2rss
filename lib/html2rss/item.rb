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

    private_class_method :new

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

    ##
    # @return [Array]
    def categories
      config.categories.map(&method(:method_missing)).uniq.keep_if { |category| category.to_s != '' }
    end

    ##
    # @return [Array]
    def self.from_url(url, config)
      page = Nokogiri::HTML(get_body_from_url(url, config.headers))
      page.css(config.selector('items')).map do |xml_item|
        new xml_item, config
      end
    end

    private

    def self.get_body_from_url(url, headers)
      Faraday.new(url: url, headers: headers) { |faraday|
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter Faraday.default_adapter
      }.get.body
    end
    private_class_method :get_body_from_url

    attr_reader :xml, :config

    def post_process(value, post_process_options)
      return value unless post_process_options

      [post_process_options].flatten.each do |options|
        value = AttributePostProcessors.get_processor(options['name'])
                                       .new(value, options, self)
                                       .get
      end

      value
    end
  end
end
