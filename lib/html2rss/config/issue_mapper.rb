# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Maps internal Dry::Validation messages to {ValidationIssue} (predicate → code).
    # Not a public API — Dry stays inside Validator / this mapper.
    module IssueMapper
      module_function

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

      ##
      # @param message [Dry::Schema::Message, #path, #text, #predicate, #input]
      # @param values [Hash, nil]
      # @return [Html2rss::Config::ValidationIssue]
      def issue_for(message, values: nil)
        path = normalize_path(message.path)
        ValidationIssue.new(
          path:,
          code: code_for(message),
          message: message.text,
          expected: expected_for(path, values),
          actual: actual_for(path, values, message)
        )
      end

      def code_for(message)
        PREDICATE_CODES.fetch(message.predicate, :invalid_value)
      end
      module_function :code_for

      def normalize_path(path)
        Array(path).compact
      end
      module_function :normalize_path

      def actual_for(path, values, message)
        dug = dig_path(values, path)
        return dug unless dug.nil?
        return message.input if message.respond_to?(:input) && !message.input.nil?

        nil
      end
      module_function :actual_for

      def expected_for(path, values)
        return nil if values.nil? || path.empty?

        leaf = path.last
        return nil unless leaf.is_a?(Symbol)

        parent = dig_path(values, path[0...-1])
        return nil unless parent.is_a?(Hash)

        option = option_for(parent, leaf)
        return nil unless option

        { type: Selectors::SchemaDoc.json_type_for(option.type), required: option.required }
      end
      module_function :expected_for

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
      module_function :option_for

      def find_option(klass, leaf)
        Selectors::SchemaDoc.options_for(klass).find { |spec| spec.name == leaf }
      end
      module_function :find_option

      def dig_path(values, path)
        return nil if values.nil? || path.empty?

        path.reduce(values) do |cursor, segment|
          break nil if cursor.nil?
          next cursor[segment] if cursor.is_a?(Hash)
          next cursor[segment] if cursor.is_a?(Array) && segment.is_a?(Integer)

          break nil
        end
      end
      module_function :dig_path
    end
  end
end
