# frozen_string_literal: true

module RuboCop
  module Cop
    module Html2rss
      # Forbids console writes from library code; log through +Html2rss::Log+.
      #
      # Flags receiverless or +Kernel.+ +warn+, +puts+, +print+, +printf+, +putc+,
      # +p+ and +pp+, and any reference to +$stdout+, +$stderr+, +STDOUT+ or
      # +STDERR+ except as the device handed to +Logger.new+ (the log sink).
      # The CLI owns user-facing output and is excluded in +.rubocop.yml+.
      # Never disable this cop inline.
      class NoConsoleOutput < Base
        MSG = 'Log through Html2rss::Log instead of writing to the console (`%<name>s`).'

        WRITE_METHODS = %i[warn puts print printf putc p pp].to_set.freeze
        STREAM_GLOBALS = %i[$stdout $stderr].to_set.freeze
        STREAM_CONSTANTS = %i[STDOUT STDERR].to_set.freeze

        # @param node [RuboCop::AST::SendNode]
        # @return [void]
        def on_send(node)
          return unless WRITE_METHODS.include?(node.method_name)
          return unless node.receiver.nil? || kernel?(node.receiver)

          add_offense(node, message: format(MSG, name: node.method_name))
        end

        # @param node [RuboCop::AST::GlobalVariableNode]
        # @return [void]
        def on_gvar(node)
          stream_offense(node, node.name) if STREAM_GLOBALS.include?(node.name)
        end

        # @param node [RuboCop::AST::ConstNode]
        # @return [void]
        def on_const(node)
          return unless STREAM_CONSTANTS.include?(node.short_name) && top_level?(node)

          stream_offense(node, node.short_name)
        end

        private

        def stream_offense(node, name)
          add_offense(node, message: format(MSG, name:)) unless logger_device?(node)
        end

        def logger_device?(node)
          parent = node.parent
          parent&.method?(:new) && const_named?(parent.receiver, :Logger) &&
            parent.first_argument.equal?(node)
        end

        def kernel?(receiver) = const_named?(receiver, :Kernel)

        def const_named?(node, name)
          node&.const_type? && top_level?(node) && node.short_name == name
        end

        def top_level?(node)
          node.namespace.nil? || node.namespace.cbase_type?
        end
      end
    end
  end
end
