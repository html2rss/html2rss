# frozen_string_literal: true

require 'yaml'

module Html2rss
  module Registry
    ##
    # Loads a verified registry bundle directory.
    class Bundle
      # Verified bundle payload returned by {.load}.
      BundleData = Data.define(:manifest, :configs, :catalog_entries)

      ##
      # @param directory [String] bundle root directory
      # @param trust [Symbol] +:signed+ or +:integrity_only+
      # @param public_keys [Hash{String => OpenSSL::PKey::PKey}] key id => public key
      # @return [BundleData]
      def self.load(directory, trust:, public_keys: {})
        manifest = Verifier.verify!(directory, trust:, public_keys:)
        path_configs = load_path_configs!(directory, manifest)
        configs = index_by_entry_id!(path_configs)
        catalog_entries = CatalogBuilder.entries_from_configs(path_configs)

        BundleData.new(manifest:, configs:, catalog_entries:)
      end

      ##
      # @param directory [String]
      # @param manifest [Manifest]
      # @return [Hash{String => Hash}] relative_path => validated config
      def self.load_path_configs!(directory, manifest)
        manifest.files.keys.sort.to_h do |relative_path|
          [relative_path, load_config!(directory, relative_path)]
        end
      end

      ##
      # @param path_configs [Hash{String => Hash}]
      # @return [Hash{String => Hash}] registry.id and aliases => config
      def self.index_by_entry_id!(path_configs)
        configs = {}
        path_configs.each do |relative_path, config|
          primary_id = CatalogBuilder.entry_id(config, relative_path)
          register_entry_id!(configs, primary_id, config, label: 'registry.id')

          Array(config.dig(:registry, :aliases)).map(&:to_s).reject(&:empty?).each do |alias_id|
            register_entry_id!(configs, alias_id, config, label: 'alias')
          end
        end
        configs
      end

      ##
      # @param configs [Hash{String => Hash}]
      # @param id [String]
      # @param config [Hash]
      # @param label [String]
      # @return [void]
      def self.register_entry_id!(configs, id, config, label:)
        raise InvalidConfig, "Duplicate or conflicting #{label}: #{id}" if configs.key?(id)

        configs[id] = config
      end

      ##
      # @param directory [String]
      # @param relative_path [String]
      # @return [Hash]
      def self.load_config!(directory, relative_path)
        absolute_path = BundleRelativePath.resolve_config!(directory, relative_path)
        config = YAML.safe_load_file(absolute_path, symbolize_names: true)
        validate_config!(relative_path, config)
        config
      end

      ##
      # @param relative_path [String]
      # @param config [Hash]
      # @return [void]
      def self.validate_config!(relative_path, config)
        result = Config.validate(config)
        return if result.success?

        message = result.errors(full: true).map(&:text).join('; ')
        raise InvalidConfig, "Invalid config #{relative_path}: #{message}"
      end
      private_class_method :load_path_configs!, :index_by_entry_id!, :register_entry_id!,
                           :load_config!, :validate_config!
    end
  end
end
