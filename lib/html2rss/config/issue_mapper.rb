# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Maps internal Dry::Validation messages to {ValidationIssue} (predicate → code).
    # Not a public API — Dry stays inside Validator / this mapper.
    module IssueMapper
      # Dry schema predicates → closed {ValidationIssue::CODES}.
      PREDICATE_CODES = {
        key?: :missing_key,
        filled?: :missing_key,
        str?: :type_mismatch,
        int?: :type_mismatch,
        bool?: :type_mismatch,
        hash?: :type_mismatch,
        array?: :type_mismatch,
        type?: :type_mismatch,
        format?: :invalid_value,
        included_in?: :unknown_value,
        gt?: :constraint,
        gteq?: :constraint,
        lt?: :constraint,
        lteq?: :constraint,
        max_size?: :constraint,
        min_size?: :constraint
      }.freeze

      class << self
        ##
        # @param dry_result [Dry::Validation::Result]
        # @param values [Hash, nil] config under validation (for actual/expected dig)
        # @return [Html2rss::Config::ValidationReport]
        def from(dry_result, values: nil)
          return ValidationReport.ok if dry_result.success?

          ValidationReport.failure(dry_result.errors.map { |message| issue_for(message, values:) })
        end

        ##
        # @param message [String]
        # @return [Html2rss::Config::ValidationReport]
        def parse_failure(message)
          ValidationReport.failure(
            [
              ValidationIssue.new(path: %i[parse], code: :parse, message:)
            ]
          )
        end

        private

        def issue_for(message, values:)
          path = Array(message.path).compact
          ValidationIssue.new(
            path:,
            code: PREDICATE_CODES.fetch(message.predicate, :invalid_value),
            message: message.text,
            expected: expected_for(path, values),
            actual: actual_for(path, values, message)
          )
        end

        def actual_for(path, values, message)
          dug = dig_path(values, path)
          return dug unless dug.nil?
          return message.input if message.respond_to?(:input) && !message.input.nil?

          nil
        end

        def expected_for(path, values)
          return if values.nil? || path.empty?
          return unless path.last.is_a?(Symbol)

          parent = dig_path(values, path[0...-1])
          return unless parent.is_a?(Hash)

          option = option_for(parent, path.last)
          return unless option

          { type: Selectors::SchemaDoc.json_type_for(option.type), required: option.required }
        end

        def option_for(parent, leaf)
          if (name = parent[:extractor] || parent['extractor'])
            klass = Selectors::Extractors::NAME_TO_CLASS[name.to_sym]
            return find_option(klass, leaf) if klass
          end

          if (name = parent[:name] || parent['name'])
            klass = Selectors::PostProcessors::NAME_TO_CLASS[name.to_sym]
            return find_option(klass, leaf) if klass
          end

          nil
        end

        def find_option(klass, leaf)
          Selectors::SchemaDoc.options_for(klass).find { |spec| spec.name == leaf }
        end

        def dig_path(values, path)
          return if values.nil? || path.empty?

          path.reduce(values) do |cursor, segment|
            break unless cursor.is_a?(Hash) || (cursor.is_a?(Array) && segment.is_a?(Integer))

            cursor[segment]
          end
        end
      end
    end
  end
end
