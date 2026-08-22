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
        catalog_entries = CatalogBuilder.entries(directory)

        BundleData.new(manifest:, configs:, catalog_entries:)
      end

      ##
      # @param directory [String]
      # @param manifest [Manifest]
      # @return [Hash{String => Hash}]
      def self.load_configs!(directory, manifest)
        manifest.files.keys.sort.each_with_object({}) do |relative_path, configs|
          config = YAML.safe_load_file(File.join(directory, relative_path), symbolize_names: true)
          validate_config!(relative_path, config)
          configs[CatalogBuilder.entry_id(relative_path)] = config
        end
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
