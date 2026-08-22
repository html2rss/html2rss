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
        configs = load_configs!(directory, manifest)
        catalog_entries = CatalogBuilder.entries(directory, manifest:)

        BundleData.new(manifest:, configs:, catalog_entries:)
      end

      ##
      # @param directory [String]
      # @param manifest [Manifest]
      # @return [Hash{String => Hash}]
      def self.load_configs!(directory, manifest)
        entry_ids = []
        configs = manifest.files.keys.sort.each_with_object({}) do |relative_path, loaded|
          loaded.merge!(load_config_entry(directory, relative_path, entry_ids))
        end
        reject_duplicate_registry_ids!(entry_ids)
        configs
      end

      ##
      # @param directory [String]
      # @param relative_path [String]
      # @param entry_ids [Array<String>]
      # @return [Hash{String => Hash}]
      def self.load_config_entry(directory, relative_path, entry_ids)
        absolute_path = BundleRelativePath.resolve_config!(directory, relative_path)
        config = YAML.safe_load_file(absolute_path, symbolize_names: true)
        validate_config!(relative_path, config)
        entry_id = CatalogBuilder.entry_id(config, relative_path)
        entry_ids << entry_id
        { entry_id => config }
      end

      ##
      # @param entry_ids [Array<String>]
      # @return [void]
      def self.reject_duplicate_registry_ids!(entry_ids)
        duplicates = entry_ids.group_by(&:itself).select { |_, group| group.size > 1 }.keys
        return if duplicates.empty?

        raise InvalidConfig, "Duplicate registry.id values: #{duplicates.sort.join(', ')}"
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
    end
  end
end
