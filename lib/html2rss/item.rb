# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'
require 'json'
require 'nokogiri'

module Html2rss
  ##
  # Takes the selected Nokogiri::HTML and responds to accessors names
  # defined in the feed config.
  class Item
    Context = Struct.new('Context', :options, :item, :config, keyword_init: true)

    ##
    # @param xml [Nokogiri::XML::Element]
    # @param config [Html2rss::Config]
    def initialize(xml, config)
      @xml = xml
      @config = config
    end

    private_class_method :new

    ##
    # @param method_name [Symbol]
    # @param _include_private [true, false]
    def respond_to_missing?(method_name, _include_private = false)
      config.attribute?(method_name) || super
    end

    ##
    # @param method_name [Symbol]
    # @param _args [Object]
    # @return [String]
    def method_missing(method_name, *_args)
      return super unless respond_to_missing?(method_name)

      attribute_options = config.selector_attributes_with_channel(method_name)

      post_process(
        ItemExtractors.item_extractor_factory(attribute_options, xml).get,
        attribute_options.fetch(:post_process, false)
      )
    end

    ##
    # @return [Array<Symbol>]
    def available_attributes
      @available_attributes ||= (%i[title link description author comments updated] &
        config.attribute_names) - %i[categories enclosure]
    end

    ##
    # At least a title or a description is required to be a valid RSS 2.0 item.
    # @return [true, false]
    def valid?
      title_or_description.to_s != ''
    end

    ##
    # Returns the title or, if absent, the description. Returns nil if both are absent.
    # @return [String, nil]
    def title_or_description
      return title if config.attribute?(:title)

      description if config.attribute?(:description)
    end

    ##
    #
    # @return [String] SHA1
    def guid
      content = config.guid_selectors.flat_map { |method_name| public_send(method_name) }.join

      Digest::SHA1.hexdigest content
    end

    ##
    # @return [Array<String>]
    def categories
      config.category_selectors.map { |method_name| public_send(method_name) }
    end

    ##
    # @return [true, false]
    def enclosure?
      config.attribute?(:enclosure)
    end

    ##
    # @return [URI::HTTPS, URI::HTTP]
    def enclosure_url
      enclosure = Html2rss::Utils.sanitize_url(method_missing(:enclosure))

      Html2rss::Utils.build_absolute_url_from_relative(enclosure, config.url).to_s if enclosure
    end

    ##
    # @param url [URI::HTTPS, URI::HTTP, Addressable::URI]
    # @param config [Html2rss::Config]
    # @return [Array<Html2rss::Item>]
    def self.from_url(url, config)
      body = get_body_from_url(url, config)

      Nokogiri.HTML(body).css(config.selector(Config::Selectors::ITEMS_SELECTOR_NAME))
              .map { |xml_item| new xml_item, config }
              .keep_if(&:valid?)
    end

    ##
    # @param url [String, URI::HTTPS, URI::HTTP, Addressable::URI]
    # @param config [Html2rss::Config]
    # @return [String]
    def self.get_body_from_url(url, config)
      body = Faraday.new(url: url, headers: config.headers) do |faraday|
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter Faraday.default_adapter
      end.get.body

      config.json? ? Html2rss::Utils.object_to_xml(JSON.parse(body)) : body
    end

    private

    # @return [Nokogiri::XML::Element]
    attr_reader :xml
    # @return [Html2rss::Config]
    attr_reader :config

    ##
    # @param value [String]
    # @param post_process_options [Hash<Symbol, Object>]
    # @return [String]
    def post_process(value, post_process_options)
      return value unless post_process_options

      [post_process_options].flatten.each do |options|
        value = AttributePostProcessors.get_processor(options[:name])
                                       .new(value, Context.new(options: options, item: self, config: config))
                                       .get
      end

      value
    end
  end
end
