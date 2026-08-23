# frozen_string_literal: true

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

      class << self
        ##
        # Assembles catalog rows from already-loaded configs (no disk I/O).
        #
        # @param path_configs [Hash{String => Hash}] relative_path => validated config
        # @return [Array<CatalogEntry>] sorted catalog entries
        def entries_from_configs(path_configs)
          path_configs.keys.sort
                      .filter_map { |relative_path| assemble_entry(relative_path, path_configs.fetch(relative_path)) }
                      .sort_by(&:id)
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

        private

        def require_directory_title!(directory, relative_path)
          title = directory[:title]
          raise MissingDirectoryTitle, "Missing directory.title in #{relative_path}" if title.to_s.strip.empty?

          title
        end

        def default_parameters(parameters)
          return {} unless parameters.is_a?(Hash)

          parameters.filter_map do |name, config|
            next unless config.is_a?(Hash) && config.key?(:default)

            [name.to_s, config[:default]]
          end.to_h
        end

        def parameter_schema(channel_url, parameters)
          schema = url_parameter_types(channel_url)
          return schema unless parameters.is_a?(Hash)

          parameters.each do |name, config|
            next unless config.is_a?(Hash)

            schema[name.to_s] = config.slice(:type).transform_keys(&:to_s)
          end
          schema
        end

        def url_parameter_types(url)
          url.to_s.scan(/%[{<](\w+)[>}](\w)?/).to_h do |name, format|
            [name, { 'type' => numeric_format?(format) ? 'integer' : 'string' }]
          end
        end

        def numeric_format?(format) = %w[i d u].include?(format)
      end
    end
  end
end
