# frozen_string_literal: true

require 'rbconfig'

module RuboCop
  module Cop
    module Html2rss
      # Requires errors raised or defined in +lib/+ to descend from +Html2rss::Error+.
      #
      # A core error is any exception class Ruby itself defines at boot ({CORE_ERRORS}): +ArgumentError+,
      # +IOError+, +Errno::ENOENT+, +Encoding::CompatibilityError+ and the rest, spelled bare, +::+- or
      # +Object::+-qualified. Flags:
      #
      # - +raise+/+fail+ of a core class, or of an instance built from one (+.new+, +.exception+);
      # - +raise+/+fail+ of a string-producing expression (an implicit +RuntimeError+): a string literal,
      #   +format+/+sprintf+, +to_s+/+inspect+/+join+/+message+, a method called on a string, or +++/+<<+/+%+ with a
      #   string operand;
      # - a class or +Class.new+ subclassing a core class, and a constant aliasing one (+Alias = IOError+).
      #
      # Re-raising (+raise+, +raise error+), raising a value returned by a method, and raising a library's
      # own class (+Thor::Error+, +Timeout::Error+: not defined at boot) stay allowed. Only the root
      # +Html2rss::Error < StandardError+ may subclass a core class. Never disable this cop inline; define
      # the error next to its owner.
      class LocalErrorClass < Base
        MSG = 'Raise or subclass an Html2rss::Error subclass defined next to its owner, not `%<name>s`.'

        # Lists every exception constant reachable from +Object+ in a Ruby booted without gems or
        # +RUBYOPT+, so classes loaded by RuboCop or its plugins never count as core.
        BOOT_ERRORS_SCRIPT = <<~RUBY
          seen = { Object => true }
          walk = lambda do |mod, prefix|
            mod.constants(false).each do |name|
              next if mod.autoload?(name)

              value = mod.const_get(name, false)
              path = [prefix, name].compact.join('::')
              puts path if value.is_a?(Class) && value <= Exception
              next unless value.is_a?(Module) && !seen[value]

              seen[value] = true
              walk.call(value, path)
            end
          end
          walk.call(Object, nil)
        RUBY

        # Fully qualified names of the exception classes Ruby defines at boot.
        CORE_ERRORS = IO.popen([RbConfig.ruby, '--disable=all', '-e', BOOT_ERRORS_SCRIPT], &:read)
                        .split.to_set.freeze
        raise "#{name}: listing boot exception classes failed" if CORE_ERRORS.empty?

        RAISE_METHODS = %i[raise fail].to_set.freeze
        STRING_FORMATTERS = %i[format sprintf].to_set.freeze
        STRING_CONVERSIONS = %i[to_s to_str inspect join message full_message].to_set.freeze
        STRING_OPERATORS = %i[+ << %].to_set.freeze

        ROOT_ERROR = 'Html2rss::Error'

        # @param node [RuboCop::AST::SendNode]
        # @return [void]
        def on_send(node)
          offense_name = raised_core_error(node) || class_new_core_error(node)
          add_offense(node, message: format(MSG, name: offense_name)) if offense_name
        end

        # @param node [RuboCop::AST::ClassNode]
        # @return [void]
        def on_class(node)
          name = core_error_name(node.parent_class)
          return unless name
          return if root_error?(node)

          add_offense(node.parent_class, message: format(MSG, name:))
        end

        # @param node [RuboCop::AST::CasgnNode]
        # @return [void]
        def on_casgn(node)
          name = core_error_name(node.expression)
          add_offense(node.expression, message: format(MSG, name:)) if name
        end

        private

        def raised_core_error(node)
          return unless raise_call?(node)

          subject = node.first_argument
          return 'RuntimeError' if string_expression?(subject)

          core_error_name(subject) || core_error_name(subject&.receiver)
        end

        def raise_call?(node)
          RAISE_METHODS.include?(node.method_name) && (node.receiver.nil? || const_named?(node.receiver, 'Kernel'))
        end

        def string_expression?(node)
          return false unless node
          return true if node.type?(:str, :dstr, :xstr)
          return string_expression?(node.children.last) if node.begin_type?
          return false unless node.send_type?

          string_send?(node)
        end

        def string_send?(node)
          return true if node.receiver && STRING_CONVERSIONS.include?(node.method_name)
          return true if STRING_FORMATTERS.include?(node.method_name) && kernel_receiver?(node.receiver)
          return true if string_expression?(node.receiver)

          STRING_OPERATORS.include?(node.method_name) && string_expression?(node.first_argument)
        end

        def kernel_receiver?(receiver)
          receiver.nil? || const_named?(receiver, 'Kernel')
        end

        def class_new_core_error(node)
          return unless node.method?(:new) && const_named?(node.receiver, 'Class')

          core_error_name(node.first_argument)
        end

        def core_error_name(node)
          name = top_level_name(node)
          name if CORE_ERRORS.include?(name)
        end

        def const_named?(node, name)
          top_level_name(node) == name
        end

        # @return [String, nil] the constant path from the top level (+::+ and +Object::+ prefixes dropped),
        #   or nil when the node is not a constant path anchored at the top level
        def top_level_name(node)
          return unless node&.const_type?

          namespace = node.namespace
          return node.short_name.to_s if namespace.nil? || namespace.cbase_type? || const_named?(namespace, 'Object')

          prefix = top_level_name(namespace)
          "#{prefix}::#{node.short_name}" if prefix
        end

        def root_error?(node)
          namespaces = node.each_ancestor(:module, :class).map { |scope| scope.identifier.const_name }
          [*namespaces.reverse, node.identifier.const_name].join('::') == ROOT_ERROR &&
            node.parent_class.short_name == :StandardError
        end
      end
    end
  end
end
