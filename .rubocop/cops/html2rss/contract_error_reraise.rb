# frozen_string_literal: true

module RuboCop
  module Cop
    module Html2rss
      # Keeps programmer errors out of operational rescues: a clause that also catches
      # +Html2rss::ContractError+ must be preceded, in the same rescue, by a clause that re-raises it.
      #
      # Flags a +rescue+ clause naming +Html2rss::Error+ (bare +Error+, +::+-qualified or not),
      # +StandardError+, +Exception+, or no class at all (bare +rescue+, +rescue => e+, the +rescue+
      # modifier), unless an earlier clause of the same +begin+/+def+/block catches +ContractError+
      # (or anything broader) and ends in a bare +raise+ or +raise <variable>+. A clause whose own
      # body re-raises is never flagged (it swallows nothing).
      #
      # Unqualified +Error+ is read as +Html2rss::Error+ wherever it appears (conservative: flagged
      # even outside +module Html2rss+); +Zlib::Error+, +RSS::Error+ and other qualified names are
      # not. A splatted list (+rescue *ERRORS+) is not resolved: put +ContractError+ in the clause
      # that re-raises, and keep the splat list free of broad classes.
      # Never disable this cop inline.
      class ContractErrorReraise < Base
        MSG = 'Re-raise Html2rss::ContractError first: add `rescue Html2rss::ContractError` + `raise` before this clause.'

        CORE = %i[StandardError Exception].to_set.freeze
        BROAD = (CORE | %i[Error]).freeze
        GUARDS = (BROAD | %i[ContractError]).freeze

        # @param node [RuboCop::AST::RescueNode]
        # @return [void]
        def on_rescue(node)
          guarded = false
          node.resbody_branches.each do |resbody|
            reraises = reraises?(resbody)
            guarded ||= reraises && catches?(resbody, GUARDS)
            add_offense(resbody.loc.keyword) if !guarded && catches?(resbody, BROAD)
          end
        end

        private

        def catches?(resbody, names)
          exceptions = resbody.exceptions
          return true if exceptions.empty?

          exceptions.any? { |exception| named?(exception, names) }
        end

        def named?(node, names)
          return false unless node.const_type? && names.include?(node.short_name)

          namespace = node.namespace
          return true if namespace.nil? || namespace.cbase_type?

          owner = CORE.include?(node.short_name) ? :Object : :Html2rss
          const_named?(namespace, owner) && (namespace.namespace.nil? || namespace.namespace.cbase_type?)
        end

        def const_named?(node, name)
          node.const_type? && node.short_name == name
        end

        # The clause ends in a bare +raise+ or +raise <its own variable>+.
        def reraises?(resbody)
          last = resbody.body
          last = last.children.last if last&.begin_type?
          return false unless last&.send_type? && last.method?(:raise) && last.receiver.nil?

          last.arguments.empty? || own_variable?(resbody, last)
        end

        def own_variable?(resbody, raise_node)
          variable = resbody.exception_variable
          argument = raise_node.first_argument
          raise_node.arguments.one? && variable && argument.lvar_type? &&
            argument.children.first == variable.children.first
        end
      end
    end
  end
end
