# frozen_string_literal: true

module RuboCop
  module Cop
    module Html2rss
      # Requires errors raised or defined in +lib/+ to descend from +Html2rss::Error+.
      #
      # Flags +raise+/+fail+ of a core exception class (bare, +::+-qualified or
      # +.new+), +raise 'message'+ (an implicit RuntimeError), and a local class
      # that subclasses a core exception instead of +Html2rss::Error+. Re-raising
      # a rescued error (+raise+, +raise error+) and raising a library's own class
      # stay allowed. Only the root +Html2rss::Error < StandardError+ may subclass
      # a core class. Never disable this cop inline; define the error next to its owner.
      class LocalErrorClass < Base
        MSG = 'Raise or subclass an Html2rss::Error subclass defined next to its owner, not `%<name>s`.'

        CORE_ERRORS = %i[
          Exception StandardError RuntimeError ScriptError NotImplementedError
          ArgumentError TypeError KeyError IndexError RangeError NameError NoMethodError
        ].to_set.freeze

        RAISE_METHODS = %i[raise fail].to_set.freeze

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

        private

        def raised_core_error(node)
          return unless raise_call?(node)

          subject = node.first_argument
          return 'RuntimeError' if subject&.type?(:str, :dstr)

          core_error_name(subject) || core_error_name(new_receiver(subject))
        end

        def raise_call?(node)
          RAISE_METHODS.include?(node.method_name) && (node.receiver.nil? || kernel?(node.receiver))
        end

        def class_new_core_error(node)
          return unless node.method?(:new) && const_named?(node.receiver, :Class)

          core_error_name(node.first_argument)
        end

        def new_receiver(node)
          node.receiver if node&.send_type? && node.method?(:new)
        end

        def core_error_name(node)
          return unless node&.const_type? && top_level_const?(node)

          node.short_name.to_s if CORE_ERRORS.include?(node.short_name)
        end

        def top_level_const?(node)
          node.namespace.nil? || node.namespace.cbase_type?
        end

        def kernel?(receiver)
          const_named?(receiver, :Kernel)
        end

        def const_named?(node, name)
          node&.const_type? && top_level_const?(node) && node.short_name == name
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
