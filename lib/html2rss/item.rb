# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  ##
  # Takes the selected Nokogiri::HTML and responds to accessors names
  # defined in the feed config.
  #
  # Instances can only be created via `.from_url` and
  # each represents a internally used "RSS item".
  # Such an item provides the dynamically defined attributes as a method.
  class Item
    Context = Struct.new('Context', :options, :item, :config, keyword_init: true)
    Enclosure = Struct.new('Enclosure', :type, :bits_length, :url, keyword_init: true)

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

      extract method_name
    end

    ##
    # Selects and processes according to the selector name.
    #
    # @param selector_name [Symbol, #to_sym]
    # @return [String] the extracted value for the selector.
    def extract(selector_name)
      attribute_options = config.selector_attributes_with_channel(selector_name.to_sym)

      post_process(
        ItemExtractors.item_extractor_factory(attribute_options, xml).get,
        attribute_options.fetch(:post_process, false)
      )
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
    # @return [Enclosure]
    def enclosure
      url = enclosure_url

      raise 'An item.enclosure requires an absolute URL' if !url || !url.absolute?

      content_type = MIME::Types.type_for(File.extname(url).delete('.'))

      Enclosure.new(
        type: content_type.any? ? content_type.first.to_s : 'application/octet-stream',
        bits_length: 0,
        url: url
      )
    end

    ##
    # @param url [String, Addressable::URI]
    # @param config [Html2rss::Config]
    # @return [Array<Html2rss::Item>]
    def self.from_url(url, config)
      body = Utils.request_body_from_url(url, convert_json_to_xml: config.json?, headers: config.headers)

      Nokogiri.HTML(body)
              .css(config.selector(Config::Selectors::ITEMS_SELECTOR_NAME))
              .map { |xml| new xml, config }
              .keep_if(&:valid?)
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

    ##
    # @return [Addressable::URI, nil] the (absolute) URL of the content
    def enclosure_url
      enclosure = Html2rss::Utils.sanitize_url(extract(:enclosure))

      Html2rss::Utils.build_absolute_url_from_relative(enclosure, config.url) if enclosure
    end
  end
end
