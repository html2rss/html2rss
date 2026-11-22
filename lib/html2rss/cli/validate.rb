# frozen_string_literal: true

module Html2rss
  class CLI
    ##
    # Validate command: file/glob/stdin branching and multi-file reporting.
    module Validate
      ##
      # @param files [Array<String>]
      # @param params [Hash]
      # @param quiet [Boolean]
      # @return [void]
      # @raise [Thor::Error]
      def self.run(files, params:, quiet:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        target_files = resolve_files(files)
        failed = []

        target_files.each do |file|
          result = validate_file(file, params:)

          if result.success?
            puts(target_files.size == 1 ? 'Configuration is valid' : "ok   #{file}") unless quiet
          else
            raise Thor::Error, format_failure(result) if target_files.size == 1

            warn "FAIL #{file}"
            result.issues.each { |issue| warn "       #{issue}" }
            failed << file
          end
        end

        return if failed.empty?

        raise Thor::Error, "#{failed.size}/#{target_files.size} configurations failed validation."
      end

      ##
      # @param files [Array<String>]
      # @return [Array<String>]
      def self.resolve_files(files)
        return ['-'] if files.empty? || files == ['-']

        resolved = []
        files.each do |f|
          matched = Dir.glob(f)
          resolved.concat(matched.empty? ? [f] : matched)
        end
        resolved.uniq
      end

      class << self
        private

        def validate_file(file, params:)
          if file == '-'
            Html2rss.validate($stdin.read, params:)
          else
            Html2rss.validate(file, params:)
          end
        end

        def format_failure(report)
          "Invalid configuration: #{report}"
        end
      end
    end
  end
end
