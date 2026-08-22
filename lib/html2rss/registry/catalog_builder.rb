# frozen_string_literal: true

require 'yaml'

module Html2rss
  module Registry
    ##
    # Builds catalog entries from validated registry bundle configs.
    module CatalogBuilder
      # Raised when catalog assembly fails.
      class Error < Html2rss::Registry::Error; end
      # Raised when directory.title is missing from a bundled config.
      class MissingDirectoryTitle < Error; end
      # Raised when registry.id is missing from a bundled config.
      class MissingRegistryId < Error; end

      module_function

      ##
      # @param bundle_dir [String] extracted registry bundle root
      # @param manifest [Manifest] verified manifest listing config paths
      # @return [Array<CatalogEntry>] sorted catalog entries
      def entries(bundle_dir, manifest:)
        manifest.files.keys.sort.filter_map do |relative_path|
          build_entry(bundle_dir, relative_path)
        end.sort_by(&:id)
      end

      ##
      # @param bundle_dir [String]
      # @param relative_path [String] path relative to bundle root, e.g. configs/foo/bar.yml
      # @return [CatalogEntry]
      def build_entry(bundle_dir, relative_path)
        absolute_path = BundleRelativePath.resolve_config!(bundle_dir, relative_path)
        config = load_config(absolute_path)
        assemble_entry(relative_path, config)
      end

      ##
      # @param relative_path [String]
      # @param config [Hash]
      # @return [CatalogEntry]
      def assemble_entry(relative_path, config)
        title = require_directory_title!(config.fetch(:directory, {}), relative_path)
        id = entry_id(config, relative_path)

        CatalogEntry.new(
          id:, path: "/#{id}.rss",
          directory: directory_payload(config.fetch(:directory, {}), title),
          channel: channel_payload(config.fetch(:channel, {}), title),
          parameters: parameters_payload(config.fetch(:channel, {}), config[:parameters])
        )
      end

      ##
      # @param config [Hash]
      # @param relative_path [String]
      # @return [String]
      def entry_id(config, relative_path = nil)
        id = config.dig(:registry, :id)
        raise MissingRegistryId, "Missing registry.id in #{relative_path}" if id.to_s.strip.empty?

        id.to_s
      end

      ##
      # @param path [String]
      # @return [Hash]
      def load_config(path)
        YAML.safe_load_file(path, symbolize_names: true)
      end

      ##
      # @param directory [Hash]
      # @param relative_path [String]
      # @return [String]
      def require_directory_title!(directory, relative_path)
        title = directory[:title]
        raise MissingDirectoryTitle, "Missing directory.title in #{relative_path}" if title.to_s.strip.empty?

        title
      end

      ##
      # @param directory [Hash]
      # @param title [String]
      # @return [Hash{Symbol => Object}]
      def directory_payload(directory, title)
        {
          title: title.to_s,
          summary: directory[:summary],
          topics: Array(directory[:topics])
        }.compact
      end

      ##
      # @param channel [Hash]
      # @param title [String]
      # @return [Hash{Symbol => Object}]
      def channel_payload(channel, title)
        {
          url: channel.fetch(:url),
          language: channel[:language],
          title: channel[:title] || title.to_s
        }.compact
      end

      ##
      # @param channel [Hash]
      # @param parameters_block [Hash, nil]
      # @return [Hash{Symbol => Object}]
      def parameters_payload(channel, parameters_block)
        {
          schema: parameter_schema(channel.fetch(:url), parameters_block),
          defaults: default_parameters(parameters_block)
        }
      end

      ##
      # @param parameters [Hash, nil]
      # @return [Hash{String => Object}]
      def default_parameters(parameters)
        return {} unless parameters.is_a?(Hash)

        parameters.each_with_object({}) do |(name, config), defaults|
          next unless config.is_a?(Hash) && config.key?(:default)

          defaults[name.to_s] = config[:default]
        end
      end

      ##
      # @param channel_url [String]
      # @param parameters [Hash, nil]
      # @return [Hash{String => Object}]
      def parameter_schema(channel_url, parameters)
        schema = url_parameter_types(channel_url)
        return schema unless parameters.is_a?(Hash)

        parameters.each do |name, config|
          next unless config.is_a?(Hash)

          schema[name.to_s] = config.slice(:type).transform_keys(&:to_s)
        end
        schema
      end

      ##
      # @param url [String]
      # @return [Hash{String => String}]
      def url_parameter_types(url)
        url.to_s.scan(/%[{<](\w+)[>}](\w)?/).each_with_object({}) do |(name, format), types|
          types[name] = { 'type' => numeric_format?(format) ? 'integer' : 'string' }
        end
      end

      ##
      # @param format [String, nil]
      # @return [Boolean]
      def numeric_format?(format)
        %w[i d u].include?(format)
      end
    end
  end
end
