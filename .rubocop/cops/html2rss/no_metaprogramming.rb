# frozen_string_literal: true

module RuboCop
  module Cop
    module Html2rss
      # Forbids metaprogramming and reflection in +lib/+.
      #
      # Inspects the parsed AST so comments cannot trigger it. Never disable
      # this cop inline; fix the type or call instead.
      class NoMetaprogramming < Base
        MSG = 'Avoid metaprogramming in lib/; use an explicit type or call.'

        FORBIDDEN_METHODS = %i[
          public_send send __send__
          define_method
          instance_variable_get instance_variable_set
          instance_eval class_eval module_eval eval
          instance_exec class_exec module_exec
          const_get const_set const_defined?
          respond_to?
          method_missing respond_to_missing?
          def_delegator def_delegators
        ].to_set.freeze

        FORBIDDEN_DEFS = %i[method_missing respond_to_missing?].to_set.freeze

        # @param node [RuboCop::AST::SendNode]
        # @return [void]
        def on_send(node)
          add_offense(node) if forbidden_send?(node)
        end
        alias on_csend on_send

        # @param node [RuboCop::AST::ConstNode]
        # @return [void]
        def on_const(node)
          add_offense(node) if node.short_name == :Forwardable
        end

        # @param node [RuboCop::AST::DefNode]
        # @return [void]
        def on_def(node)
          add_offense(node) if FORBIDDEN_DEFS.include?(node.method_name)
        end
        alias on_defs on_def

        private

        def forbidden_send?(node)
          forbidden_method?(node) || method_lookup?(node) ||
            data_define_block?(node) || struct_new_block?(node)
        end

        def forbidden_method?(node) = FORBIDDEN_METHODS.include?(node.method_name)

        def method_lookup?(node) = node.method?(:method) && node.arguments.any?

        def data_define_block?(node)
          node.method?(:define) && node.block_node && const_named?(node.receiver, 'Data')
        end

        def struct_new_block?(node)
          node.method?(:new) && node.block_node && const_named?(node.receiver, 'Struct')
        end

        def const_named?(receiver, name)
          receiver&.const_type? && receiver.const_name == name
        end
      end
    end
  end
end
