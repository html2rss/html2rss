# frozen_string_literal: true

require 'json'
require 'digest'

module Html2rss
  module Registry
    ##
    # Parses and emits registry.v1 manifest documents.
    class Manifest
      # Manifest format identifier.
      FORMAT = 'registry.v1'
      # Manifest file name inside a bundle directory.
      MANIFEST_FILE = 'manifest.json'
      # Signature file name inside a bundle directory.
      SIGNATURE_FILE = 'manifest.sig'
      # Required string manifest fields validated during parse.
      REQUIRED_STRING_FIELDS = %i[registry_id version public_key_id].freeze

      attr_reader :registry_id, :version, :public_key_id, :files

      ##
      # @param json [String]
      # @return [Manifest]
      def self.parse(json)
        document = JSON.parse(json, symbolize_names: true)
        validate_document!(document)

        new(
          registry_id: document.fetch(:registry_id),
          version: document.fetch(:version),
          public_key_id: document.fetch(:public_key_id),
          files: document.fetch(:files).transform_keys(&:to_s)
        )
      rescue JSON::ParserError => error
        raise ManifestError, "Invalid manifest JSON: #{error.message}"
      end

      ##
      # @param file_index [Hash{String => String}] relative path => sha256 hex digest
      # @param registry_id [String]
      # @param version [String]
      # @param public_key_id [String]
      # @return [Manifest]
      def self.build(file_index:, registry_id:, version:, public_key_id:)
        new(
          registry_id:,
          version:,
          public_key_id:,
          files: file_index.transform_keys(&:to_s)
        )
      end

      ##
      # @param document [Hash{Symbol => Object}]
      # @return [String]
      def self.canonical_bytes_for(document)
        JSON.generate(deep_sort(document))
      end

      ##
      # @param bundle_dir [String]
      # @param relative_paths [Array<String>]
      # @return [Hash{String => String}]
      def self.file_index(bundle_dir, relative_paths)
        relative_paths.each_with_object({}) do |relative_path, index|
          absolute_path = File.join(bundle_dir, relative_path)
          digest = Digest::SHA256.file(absolute_path).hexdigest
          index[relative_path] = digest
        end
      end

      ##
      # @param document [Hash]
      # @return [Hash]
      def self.deep_sort(document)
        case document
        when Hash
          document.keys.sort.to_h { |key| [key, deep_sort(document[key])] }
        when Array
          document.map { |entry| deep_sort(entry) }
        else
          document
        end
      end

      def self.validate_document!(document)
        validate_required_fields!(document)
        document[:files].each { |path, digest| validate_file_entry!(path, digest) }
      end

      def self.validate_required_fields!(document)
        raise ManifestError, 'Missing format' unless document[:format] == FORMAT

        REQUIRED_STRING_FIELDS.each do |field|
          raise ManifestError, "Missing #{field}" if document[field].to_s.empty?
        end

        return if document[:files].is_a?(Hash) && document[:files].any?

        raise ManifestError, 'Missing files'
      end

      ##
      # @param path [String, Symbol]
      # @param digest [String]
      # @return [void]
      def self.validate_file_entry!(path, digest)
        raise ManifestError, "Invalid file path #{path.inspect}" unless path.to_s.start_with?('configs/')
        return if digest.to_s.match?(/\A[0-9a-f]{64}\z/)

        raise ManifestError, "Invalid digest for #{path}"
      end

      ##
      # @param registry_id [String]
      # @param version [String]
      # @param public_key_id [String]
      # @param files [Hash{String => String}] relative path => sha256 hex digest
      def initialize(registry_id:, version:, public_key_id:, files:)
        @registry_id = registry_id
        @version = version
        @public_key_id = public_key_id
        @files = files.freeze
      end

      ##
      # @return [String] canonical JSON bytes used for signing
      def canonical_bytes
        self.class.canonical_bytes_for(to_h)
      end

      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          format: FORMAT,
          registry_id:,
          version:,
          public_key_id:,
          files: files.sort.to_h
        }
      end

      ##
      # @return [String] pretty JSON for writing manifest.json
      def to_json(*)
        "#{JSON.pretty_generate(to_h)}\n"
      end

      private_class_method :validate_document!, :validate_required_fields!, :deep_sort
    end
  end
end
