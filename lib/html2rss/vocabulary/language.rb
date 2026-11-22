# frozen_string_literal: true

module Html2rss
  module Vocabulary
    Language = Data.define(:code, :terms, :ambiguous)

    # One language: its code, its terms per concept (see {Vocabulary::CONCEPTS}) and, per scoped concept, the
    # terms that are also a common word or name outside the language's chrome meaning. An ambiguous term stays
    # in +terms+ and is repeated in +ambiguous+; it applies only when the page is in this language. A language
    # without ambiguous terms declares none.
    class Language
      # @param code [Symbol]
      # @param terms [Hash{Symbol => Array<String, Regexp>}]
      # @param ambiguous [Hash{Symbol => Array<String, Regexp>}]
      def initialize(code:, terms:, ambiguous: {}.freeze) = super
    end
  end
end
