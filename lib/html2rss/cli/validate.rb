# frozen_string_literal: true

module Html2rss
  class CLI
    ##
    # Validate command: file/glob/stdin branching and multi-file reporting.
    module Validate
      ##
      # @param files [Array<String>]
      # @param params [Hash]
      # @param out [IO] where success lines go
      # @return [void]
      # @raise [Thor::Error]
      def self.run(files, params:, out: $stdout) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if files.size == 2 && File.file?(files[0].to_s) && !File.exist?(files[1].to_s)
          raise Thor::Error, "No such file: #{files[1]}" if path_like_config?(files[1])

          run_named_feed(files[0], files[1], params:)
          out.puts 'Configuration is valid'
          return
        end

        target_files = resolve_files(files)
        failed = []

        target_files.each do |file|
          result = validate_file(file, params:)

          if result.success?
            out.puts(target_files.size == 1 ? 'Configuration is valid' : "ok   #{file}")
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

        def run_named_feed(file, feed_name, params:)
          result = Html2rss.validate(file, feed_name, params:)
          raise Thor::Error, format_failure(result) unless result.success?
        end

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

        def path_like_config?(arg)
          path = arg.to_s
          return true if path.start_with?('-')
          return true if path.end_with?('.yml', '.yaml')
          return true if path.include?('/') || path.include?('*')

          false
        end
      end
    end
  end
end
