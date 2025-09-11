# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      # Parameter object for type assertion
      class TypeAssertion
        attr_reader :value, :types, :name, :context, :caller

        def initialize(value, types, name, context:, caller: nil)
          @value = value
          @types = Array(types)
          @name = name
          @context = context
          @caller = caller
        end

        def valid_type?
          types.any? { |type| value.is_a?(type) }
        end

        def context_options
          return context[:options] if context.is_a?(Hash)

          if caller && !caller.empty?
            file_path = caller(1..1).first.split(':').first
            { file: File.basename(file_path) }
          else
            { file: File.basename(caller_locations(2, 1).first.absolute_path) }
          end
        end

        def error_message
          format('The type of `%<name>s` must be %<types>s, but is: %<type>s in: %<options>s',
                 name:,
                 types: types.join(' or '),
                 type: value.class,
                 options: context_options.inspect)
        end
      end
    end
  end
end
