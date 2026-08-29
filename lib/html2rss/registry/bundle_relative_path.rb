# frozen_string_literal: true

require 'pathname'

module Html2rss
  module Registry
    ##
    # Validates and resolves bundle-relative paths under +configs/+.
    module BundleRelativePath
      # Relative prefix for config paths inside a bundle.
      CONFIGS_PREFIX = 'configs/'

      module_function

      ##
      # @param relative_path [String, Symbol]
      # @return [String] normalized relative path
      # @raise [ManifestError] when the path is not a safe configs/ entry
      def validate_config_path!(relative_path)
        path = normalize(relative_path)
        raise ManifestError, "Invalid file path #{relative_path.inspect}" unless path.start_with?(CONFIGS_PREFIX)
        raise ManifestError, "Path traversal in #{path.inspect}" if path.split('/').include?('..')

        path
      end

      ##
      # @param relative_path [String, Symbol]
      # @return [String] normalized relative path
      # @raise [ArchiveError] when the archive entry name is unsafe
      def validate_archive_entry!(relative_path)
        path = normalize(relative_path)
        raise ArchiveError, "Absolute path in archive: #{relative_path}" if path.start_with?('/')
        raise ArchiveError, "Path traversal in archive: #{relative_path}" if path.split('/').include?('..')

        path
      end

      ##
      # @param bundle_dir [String]
      # @param relative_path [String, Symbol]
      # @return [String] absolute path under +bundle_dir/configs/+
      # @raise [VerificationError] when the path escapes +configs/+
      def resolve_config!(bundle_dir, relative_path)
        safe_relative = validate_config_path!(relative_path)
        configs_root = File.expand_path(CONFIGS_PREFIX.chop, bundle_dir)
        absolute = File.expand_path(safe_relative, bundle_dir)
        return absolute if absolute.start_with?("#{configs_root}/")

        raise VerificationError, "Path escapes configs/: #{relative_path.inspect}"
      end

      ##
      # @param relative_path [String, Symbol]
      # @return [String]
      def normalize(relative_path)
        relative_path.to_s.delete_prefix('./')
      end
    end
  end
end
