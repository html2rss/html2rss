require 'faraday'
require 'faraday_middleware'
require 'nokogiri'

module Html2rss
  ##
  # Takes the selected Nokogiri::HTML and responds to accessors names
  # defined in the feed config.
  class Item
    def initialize(xml, config)
      @xml = xml
      @config = config
    end

    private_class_method :new

    def respond_to_missing?(method_name, _include_private = false)
      config.attribute?(method_name) || super
    end

    def method_missing(method_name, *_args)
      return super unless respond_to_missing?(method_name)

      attribute_options = config.attribute_options(method_name)

      extractor = ItemExtractors.get_extractor(attribute_options['extractor'])
      value = extractor.new(xml, attribute_options).get

      post_process(value, attribute_options.fetch('post_process', false))
    end

    def available_attributes
      @available_attributes ||= (%w[title link description author comments updated] &
        @config.attribute_names) - ['categories']
    end

    ##
    # At least a title or a description is required to be a valid RSS 2.0 item.
    def valid?
      title = self.title if config.attribute?(:title)
      description = self.description if config.attribute?(:description)
      [title, description].join != ''
    end

    ##
    # @return [Array]
    def categories
      categories = config.categories
      categories.map!(&method(:method_missing))
      categories.uniq!
      categories.keep_if { |category| category.to_s != '' }
    end

    ##
    # @return [Array]
    def self.from_url(url, config)
      body = get_body_from_url(url, config)

      Nokogiri::HTML(body).css(config.selector('items')).map do |xml_item|
        new xml_item, config
      end
    end

    private

    def self.get_body_from_url(url, config)
      body = Faraday.new(url: url, headers: config.headers) do |faraday|
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter Faraday.default_adapter
      end.get.body

      config.json? ? Html2rss::Utils.hash_to_xml(JSON.parse(body)) : body
    end
    private_class_method :get_body_from_url

    attr_reader :xml, :config

    def post_process(value, post_process_options)
      return value unless post_process_options

      [post_process_options].flatten.each do |options|
        value = AttributePostProcessors.get_processor(options['name'])
                                       .new(value, options: options, item: self, config: @config)
                                       .get
      end

      value
    end
  end
end
