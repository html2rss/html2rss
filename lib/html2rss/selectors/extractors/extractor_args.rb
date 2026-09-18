# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Shared runtime args for extractors that only need a CSS selector (+Text+, +Html+).
      #
      # Field dispatch merges +base_url:+ into every config hash, but only
      # +Href::Args+ declares that member — +Extractors.get+ slices by +Args.members+,
      # so +base_url+ is silently dropped for every other extractor.
      ExtractorArgs = Data.define(:selector) do
        # @param selector [String, nil] CSS selector for the element
        def initialize(selector: nil) = super
      end
    end
  end
end
