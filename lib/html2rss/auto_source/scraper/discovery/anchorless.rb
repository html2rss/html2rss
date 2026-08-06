# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      module Discovery
        ##
        # Named APIs for the two distinct jobs historically toggled by
        # scraper option `:fallback_anchorless`.
        #
        # The config key stays for backward compatibility, but callers must use
        # these methods so the jobs are not silently conflated:
        #
        # - {class_cluster_containers} — Html discovers card-like nodes via
        #   class clustering when the page lacks usable content anchors.
        # - {permit_unanchored?} — SemanticHtml keeps already-found semantic
        #   containers even when no primary content anchor was selected.
        #
        # Field extraction (`Html::Extractor` with `fallback_anchorless: true`)
        # is a third, extractor-local concern and is not owned here.
        module Anchorless
          module_function

          ##
          # @param enabled [Boolean] value of scraper `:fallback_anchorless`
          # @return [Boolean] whether SemanticHtml may keep containers without a primary anchor
          def permit_unanchored?(enabled) = enabled

          ##
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @param minimum_selector_frequency [Integer] minimum class-group size
          # @return [Array<Nokogiri::XML::Node>] class-clustered card containers
          def class_cluster_containers(parsed_body, minimum_selector_frequency:)
            ClassClustering.call(parsed_body, minimum_selector_frequency:)
          end
        end
      end
    end
  end
end
