# frozen_string_literal: true

module RuboCop
  module Cop
    module Html2rss
      # Forbids console writes from library code; log through +Html2rss::Log+.
      #
      # Flags +warn+, +puts+, +print+, +printf+, +putc+, +p+ and +pp+ called without a receiver or on
      # +self+ or +Kernel+; +Warning.warn+; +display+ on any receiver (+Object#display+ writes to
      # +$stdout+); and any reference to +$stdout+, +$stderr+, +$>+, +$DEFAULT_OUTPUT+, +STDOUT+ or
      # +STDERR+ (bare, +::+- or +Object::+-qualified) except as the device handed to +Logger.new+
      # (the log sink). The CLI owns user-facing output and is excluded in +.rubocop.yml+.
      # Never disable this cop inline.
      class NoConsoleOutput < Base
        MSG = 'Log through Html2rss::Log instead of writing to the console (`%<name>s`).'

        WRITE_METHODS = %i[warn puts print printf putc p pp].to_set.freeze
        STREAM_GLOBALS = %i[$stdout $stderr $> $DEFAULT_OUTPUT].to_set.freeze
        STREAM_CONSTANTS = %i[STDOUT STDERR].to_set.freeze

        # @param node [RuboCop::AST::SendNode]
        # @return [void]
        def on_send(node)
          add_offense(node, message: format(MSG, name: node.method_name)) if console_write?(node)
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

        def console_write?(node)
          receiver = node.receiver
          return true if node.method?(:display)
          return true if node.method?(:warn) && const_named?(receiver, :Warning)

          WRITE_METHODS.include?(node.method_name) &&
            (receiver.nil? || receiver.self_type? || const_named?(receiver, :Kernel))
        end

        def stream_offense(node, name)
          add_offense(node, message: format(MSG, name:)) unless logger_device?(node)
        end

        def logger_device?(node)
          parent = node.parent
          parent&.method?(:new) && const_named?(parent.receiver, :Logger) &&
            parent.first_argument.equal?(node)
        end

        def const_named?(node, name)
          node&.const_type? && top_level?(node) && node.short_name == name
        end

        def top_level?(node)
          namespace = node.namespace
          namespace.nil? || namespace.cbase_type? || const_named?(namespace, :Object)
        end
      end
    end
  end
end
