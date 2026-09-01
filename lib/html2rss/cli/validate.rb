# frozen_string_literal: true

module Html2rss
  class CLI
    ##
    # Validate command: file/glob/stdin branching and multi-file reporting.
    module Validate
      module_function

      ##
      # @param files [Array<String>]
      # @param params [Hash]
      # @param quiet [Boolean]
      # @return [void]
      # @raise [Thor::Error]
      def run(files, params:, quiet:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if files.size == 2 && File.file?(files[0].to_s) && !File.exist?(files[1].to_s)
          raise Thor::Error, "No such file: #{files[1]}" if path_like_config?(files[1])

          return run_named_feed(files[0], files[1], params:, quiet:)
        end

        target_files = resolve_files(files)
        failed = []

        target_files.each do |file|
          result = validate_file(file, params:)

          if result.success?
            puts(target_files.size == 1 ? 'Configuration is valid' : "ok   #{file}") unless quiet
          else
            error_details = result.errors.to_h
            raise Thor::Error, "Invalid configuration: #{error_details}" if target_files.size == 1

            warn "FAIL #{file}"
            error_details.each { |key, msg| warn "       #{key}: #{Array(msg).join(', ')}" }
            failed << file
          end
        end

        return if failed.empty?

        raise Thor::Error, "#{failed.size}/#{target_files.size} configurations failed validation."
      end

      ##
      # @param files [Array<String>]
      # @return [Array<String>]
      def resolve_files(files)
        return ['-'] if files.empty? || files == ['-']

        resolved = []
        files.each do |f|
          matched = Dir.glob(f)
          resolved.concat(matched.empty? ? [f] : matched)
        end
        resolved.uniq
      end

      def run_named_feed(file, feed_name, params:, quiet:)
        result = Html2rss.validate(file, feed_name, params:)
        raise Thor::Error, "Invalid configuration: #{result.errors.to_h}" unless result.success?

        puts 'Configuration is valid' unless quiet
      end
      module_function :run_named_feed
      private_class_method :run_named_feed

      def validate_file(file, params:)
        if file == '-'
          Html2rss.validate($stdin.read, params:)
        else
          Html2rss.validate(file, params:)
        end
      end
      module_function :validate_file
      private_class_method :validate_file

      def path_like_config?(arg)
        path = arg.to_s
        return true if path.start_with?('-')
        return true if path.end_with?('.yml', '.yaml')
        return true if path.include?('/') || path.include?('*')

        false
      end
      module_function :path_like_config?
      private_class_method :path_like_config?
    end
  end
end
