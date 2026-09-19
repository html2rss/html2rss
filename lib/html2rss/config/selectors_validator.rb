# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    ##
    # Validates the configuration hash for :selectors.
    module SelectorsValidator
      ##
      # One selector validation error.
      Error = Data.define(:path, :text)

      ##
      # Validation result containing collected selector errors.
      Result = Data.define(:errors) do
        # @return [Boolean]
        def success? = errors.empty?

        # @return [Boolean]
        def failure? = !success?
      end

      ##
      # Validates the configuration of the :items selector
      class Items < Dry::Validation::Contract
        # Supported pagination strategy names (sole source: RequestSession::Pager).
        # @return [Array<String>]
        STRATEGY_NAMES = Html2rss::RequestSession::Pager.strategy_names

        params do
          required(:selector).filled(:string)
          optional(:order).filled(included_in?: %w[reverse])
          optional(:enhance).filled(:bool?)
          optional(:pagination)
        end

        rule(:pagination) do
          next if value.nil?

          if value.is_a?(Integer)
            key.failure('integer must be greater than 0') if value <= 0
          elsif value.is_a?(Hash)
            val_hash = value.transform_keys(&:to_sym)
            validate_pagination_hash(val_hash, key)
          else
            key.failure('must be an integer or a hash')
          end
        end

        private

        def validate_pagination_hash(val_hash, key)
          # Fail loud on explicit nil/non-positive: truthy checks would silently accept max_pages: nil.
          if val_hash.key?(:max_pages) && (!val_hash[:max_pages].is_a?(Integer) || val_hash[:max_pages] <= 0)
            key.failure('`max_pages` must be an integer greater than 0')
          end

          strategy = (val_hash[:strategy] || 'rel_next').to_s
          unless STRATEGY_NAMES.include?(strategy)
            key.failure("`strategy` must be one of: #{STRATEGY_NAMES.join(', ')}")
          end

          validate_strategy_fields(strategy, val_hash, key)
        end

        def validate_strategy_fields(strategy, val_hash, key)
          validate_custom_selector(val_hash, key) if strategy == 'custom_selector'
          validate_json_cursor(val_hash, key) if strategy == 'json_cursor'
        end

        def validate_custom_selector(val_hash, key)
          return unless val_hash[:selector].nil? || val_hash[:selector].to_s.strip.empty?

          key.failure('`custom_selector` strategy requires `selector` to be specified')
        end

        def validate_json_cursor(val_hash, key)
          return unless (val_hash[:cursor_path].nil? || val_hash[:cursor_path].to_s.strip.empty?) &&
                        (val_hash[:next_url_path].nil? || val_hash[:next_url_path].to_s.strip.empty?)

          key.failure('`json_cursor` strategy requires either `cursor_path` or `next_url_path`')
        end
      end

      ##
      # Validates the configuration of a single selector.
      class Selector < Dry::Validation::Contract
        params do
          optional(:selector)
          optional(:extractor).filled(:string)
          optional(:attribute).filled(:string)
          optional(:static).filled(:string)
          optional(:post_process).array(:hash)
        end

        rule(:selector) do
          key(:selector).failure('`selector` must be a string') if value && !value.is_a?(String)
        end

        rule(:extractor) do
          next unless value

          klass = Selectors::Extractors::NAME_TO_CLASS[value.to_sym]
          next key(:extractor).failure("unknown extractor: #{value}") unless klass

          Selectors::OptionSpec.for(klass).each do |spec|
            next unless spec.required
            next if values[spec.name]

            key(spec.name).failure("`#{spec.name}` is required for extractor `#{value}`")
          end
        end

        rule(:post_process).each do
          name = value[:name]
          next key(:post_process).failure('Missing post_processor `name`') if name.nil?

          klass = Selectors::PostProcessors::NAME_TO_CLASS[name.to_sym]
          next key(:post_process).failure("Unknown post_processor `name`: #{name}") unless klass

          post_process_option_type_errors(klass, value).each do |field, message|
            key(field).failure(message)
          end

          pattern_error = gsub_pattern_error(klass, value)
          key(:pattern).failure(pattern_error) if pattern_error
        end

        private

        def post_process_option_type_errors(klass, value)
          Selectors::OptionSpec.for(klass).filter_map do |spec|
            actual = value[spec.name]
            if actual.nil?
              [spec.name, spec.error_message(optional: false)] if spec.required
            elsif !spec.valid_type?(actual)
              [spec.name, spec.error_message(optional: !spec.required)]
            end
          end
        end

        # Same compile as Gsub#call. ArgumentError is the bound; Gsub maps
        # parser errors onto that path so admit and execute still share it.
        #
        # @param klass [Class]
        # @param value [Hash]
        # @return [String, nil]
        def gsub_pattern_error(klass, value)
          return unless klass == Selectors::PostProcessors::Gsub

          pattern = value[:pattern]
          return unless pattern.is_a?(String)

          Selectors::PostProcessors::Gsub.compiled_pattern(pattern)
          nil
        rescue ArgumentError => error
          error.message
        end
      end

      ##
      # Validates the configuration of the :enclosure Selector
      class Enclosure < Selector
        params do
          optional(:content_type).filled(:string, format?: %r{^[\w-]+/[\w-]+$})
        end
      end

      class << self
        ##
        # Shortcut to validate the config.
        # @param config [Hash] the configuration hash to validate
        # @return [Result]
        def call(config)
          errors = []
          return Result.new(errors:) unless config.is_a?(Hash)

          config.each_pair do |selector_key, selector|
            validate_entry(selector_key, selector, config, errors)
          end

          Result.new(errors:)
        end

        private

        def validate_entry(selector_key, selector, config, errors)
          case selector_key.to_sym
          when Selectors::ITEMS_SELECTOR_KEY
            collect_contract_errors(Items, selector, selector_key, errors)
          when :enclosure
            collect_contract_errors(Enclosure, selector, selector_key, errors)
          when :guid, :categories
            validate_array_selector(selector_key, selector, config, errors)
          else
            collect_contract_errors(Selector, selector, selector_key, errors)
          end
        end

        def collect_contract_errors(contract_class, selector, selector_key, errors)
          contract_class.new.call(selector).errors.each do |error|
            errors << Error.new(path: [selector_key, *error.path], text: error.text)
          end
        end

        def validate_array_selector(selector_key, selector, config, errors)
          msg = array_selector_shape_error(selector_key, selector)
          return errors << Error.new(path: [selector_key], text: msg) if msg

          check_unspecified_references(selector_key, selector, config, errors)
        end

        def array_selector_shape_error(key, selector)
          return "`#{key}` must be an array" unless selector.is_a?(Array)
          return "`#{key}` must contain at least one element" if selector.empty?

          nil
        end

        def check_unspecified_references(selector_key, selector, config, errors)
          selector.each do |name|
            next if config.key?(name.to_sym) || config.key?(name.to_s)

            errors << Error.new(path: [selector_key], text: "`#{selector_key}` references unspecified `#{name}`")
          end
        end
      end
    end
  end
end
