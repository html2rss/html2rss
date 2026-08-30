# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Unified feed config quality certification: schema + vocabulary validation
    # and live RSS item extraction quality checks.
    module Certify
      # Value object representing the result of config certification.
      CertificationReport = Data.define(:valid, :errors, :live_check) do
        ##
        # @return [Hash{Symbol => Object}]
        def to_h
          { valid:, errors:, live_check: }
        end
      end

      module_function

      ##
      # Validates a feed configuration and optionally tests live feed generation.
      #
      # @param config [Hash, nil] feed configuration hash (XOR yaml)
      # @param yaml [String, nil] feed configuration YAML string (XOR config)
      # @param check_live_feed [Boolean] whether to run live feed generation
      # @return [CertificationReport]
      def check(config: nil, yaml: nil, check_live_feed: true)
        feed_config = ConfigArgument.parse(config:, yaml:).config
        validation = Config.validate(feed_config)
        return schema_failure_report(validation) unless validation.success?
        return CertificationReport.new(valid: true, errors: nil, live_check: nil) unless check_live_feed

        live_check_report(feed_config)
      end

      def schema_failure_report(validation)
        CertificationReport.new(valid: false, errors: validation.errors.to_h, live_check: nil)
      end
      module_function :schema_failure_report
      private_class_method :schema_failure_report

      def live_check_report(feed_config)
        feed_result = Html2rss.feed_result(feed_config)
        rss = feed_result.to_rss
        items = rss.items
        warnings = []
        warnings << 'Feed produced 0 items' if items.empty?

        sample_items = extract_sample_items(items, warnings)
        valid = warnings.empty?
        live_check = { item_count: items.size, sample_items:, warnings: warnings.uniq }
        CertificationReport.new(valid:, errors: nil, live_check:)
      end
      module_function :live_check_report
      private_class_method :live_check_report

      def extract_sample_items(items, warnings)
        items.first(5).map do |item|
          title = item.title.to_s.strip
          url = item.link.to_s.strip
          warnings << "Item without title detected: #{url}" if title.empty?
          warnings << "Item with non-absolute URL detected: #{url}" unless url.start_with?('http://', 'https://')
          { title:, url: }
        end
      end
      module_function :extract_sample_items
      private_class_method :extract_sample_items
    end
  end
end
