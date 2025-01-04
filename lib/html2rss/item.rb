# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  ##
  # Takes the selected Nokogiri::HTML and responds to accessor names
  # defined in the feed config.
  #
  # Instances can only be created via `.from_url` and
  # each represents an internally used "RSS item".
  # Such an item provides dynamically defined attributes as methods.
  class Item
    # A context instance is passed to Item Extractors.
    Context = Struct.new('Context', :options, :item, :config, :scraper, keyword_init: true)
    # Class to keep an Item's <enclosure>.
    Enclosure = Struct.new('Enclosure', :type, :bits_length, :url, keyword_init: true)

    ##
    # Fetches items from a given URL using configuration settings.
    #
    # @param url [Addressable::URI] URL to fetch items from.
    # @param config [Html2rss::Config] Configuration object.
    # @return [Array<Html2rss::Item>] list of items fetched.
    def self.from_url(url, config)
      ctx = RequestService::Context.new(url:, headers: config.headers)

      body = RequestService.execute(ctx, strategy: config.strategy).body
      body = ObjectToXmlConverter.new(JSON.parse(body)).call if config.json?

      Nokogiri.HTML(body)
              .css(config.selector_string(Config::Selectors::ITEMS_SELECTOR_NAME))
              .map { |xml| new(xml, config) }
              .select(&:valid?)
    end

    ##
    # @param xml [Nokogiri::XML::Element]
    # @param config [Html2rss::Config]
    def initialize(xml, config)
      @xml = xml
      @config = config
    end

    private_class_method :new

    ##
    # Checks if the object responds to a method dynamically based on the configuration.
    #
    # @param method_name [Symbol]
    # @param _include_private [true, false]
    # @return [true, false]
    # :reek:BooleanParameter { enabled: false }
    def respond_to_missing?(method_name, _include_private = false)
      config.selector?(method_name) || super
    end

    ##
    # Dynamically extracts data based on the method name.
    #
    # @param method_name [Symbol]
    # @param _args [Array]
    # @return [String] extracted value for the selector.
    def method_missing(method_name, *_args)
      return super unless respond_to_missing?(method_name)

      extract(method_name)
    end

    ##
    # Selects and processes data according to the selector name.
    #
    # @param tag [Symbol]
    # @return [String] the extracted value for the selector.
    def extract(tag)
      attribute_options = config.selector_attributes_with_channel(tag.to_sym)

      post_process(
        ItemExtractors.item_extractor_factory(attribute_options, xml).get,
        attribute_options.fetch(:post_process, false)
      )
    end

    ##
    # Checks if the item is valid accordin to RSS 2.0 spec,
    # by ensuring it has at least a title or a description.
    #
    # @return [true, false]
    def valid?
      title_or_description.to_s != ''
    end

    ##
    # Returns either the title or the description, preferring title if available.
    #
    # @return [String, nil]
    def title_or_description
      return title if config.selector?(:title)

      description if config.selector?(:description)
    end

    ##
    #
    # @return [String] SHA1 hashed GUID.
    def guid
      content = config.guid_selector_names.flat_map { |method_name| public_send(method_name) }.join

      Digest::SHA1.hexdigest(content)
    end

    ##
    # Retrieves categories for the item based on configured category selectors.
    #
    # @return [Array<String>] list of categories.
    def categories
      config.category_selector_names
            .filter_map do |method_name|
        category = public_send(method_name)
        category.strip unless category.to_s.empty?
      end.uniq
    end

    ##
    # Checks if the item has an enclosure based on configuration.
    #
    # @return [true, false]
    def enclosure?
      config.selector?(:enclosure)
    end

    ##
    # Retrieves enclosure details for the item.
    #
    # @return [Enclosure] enclosure details.
    def enclosure
      url = enclosure_url

      raise 'An item.enclosure requires an absolute URL' unless url&.absolute?

      type = config.selector_attributes_with_channel(:enclosure)[:content_type] ||
             Html2rss::Utils.guess_content_type_from_url(url)

      Enclosure.new(
        type:,
        bits_length: 0,
        url: url.to_s
      )
    end

    private

    # @return [Nokogiri::XML::Element] XML element representing the item.
    attr_reader :xml
    # @return [Html2rss::Config] Configuration object for the item.
    attr_reader :config

    ##
    # Processes the extracted value according to post-processing options.
    #
    # @param value [String] extracted value.
    # @param post_process_options [Hash<Symbol, Object>] post-processing options.
    # @return [String] processed value.
    def post_process(value, post_process_options)
      return value unless post_process_options

      [post_process_options].flatten.each do |options|
        value = AttributePostProcessors.get_processor(options[:name])
                                       .new(value, Context.new(options:, item: self, config:))
                                       .get
      end

      value
    end

    ##
    # Retrieves the URL for the enclosure, sanitizing and ensuring it's absolute.
    #
    # @return [Addressable::URI, nil] absolute URL of the enclosure.
    def enclosure_url
      enclosure = Html2rss::Utils.sanitize_url(extract(:enclosure))

      Html2rss::Utils.build_absolute_url_from_relative(enclosure, config.url) if enclosure
    end
  end
end
