# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # Selects the best content-like anchor from a semantic container.
        class AnchorSelector # rubocop:disable Metrics/ClassLength
          AnchorFacts = Data.define(
            :anchor,
            :text,
            :destination,
            :segments,
            :heading_anchor,
            :heading_text_match,
            :score
          )

          HEADING_SELECTOR = HtmlExtractor::HEADING_TAGS.join(',').freeze
          UTILITY_PATH_SEGMENTS = %w[
            about account author category comment comments contact feedback help
            login newsletter profile register search settings share signup tag tags
            user users
          ].to_set.freeze
          CONTENT_PATH_SEGMENTS = %w[
            article articles news post posts story stories update updates
          ].to_set.freeze

          def initialize(base_url)
            @base_url = base_url
          end

          def primary_anchor_for(container)
            facts_for(container).max_by(&:score)&.anchor
          end

          private

          attr_reader :base_url

          def facts_for(container)
            heading = heading_for(container)
            heading_text = visible_text(heading)

            container.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR).each_with_object({}) do |anchor, best_by_destination|
              next if anchor.path.match?(Html::TAGS_TO_IGNORE)

              facts = build_facts(anchor, heading, heading_text)
              next unless facts

              keep_stronger_fact(best_by_destination, facts)
            end.values
          end

          def build_facts(anchor, heading, heading_text) # rubocop:disable Metrics/MethodLength
            text = visible_text(anchor)
            destination = normalized_destination(anchor)
            return unless destination

            segments = destination_segments(destination)
            return if ineligible_anchor?(anchor, text, segments)

            heading_anchor = heading_anchor?(anchor, heading)
            heading_text_match = heading_text_match?(heading_text, text)
            return unless heading_anchor || content_like_anchor?(text, segments)

            AnchorFacts.new(
              anchor:,
              text:,
              destination:,
              segments:,
              heading_anchor:,
              heading_text_match:,
              score: score_anchor(text, segments, heading_anchor, heading_text_match)
            )
          end

          def ineligible_anchor?(anchor, text, segments)
            utility_destination?(segments) ||
              utility_text?(text) ||
              icon_only_anchor?(anchor, text)
          end

          def keep_stronger_fact(best_by_destination, facts)
            current = best_by_destination[facts.destination]
            return best_by_destination[facts.destination] = facts unless current
            return if current.score >= facts.score

            best_by_destination[facts.destination] = facts
          end

          def content_like_anchor?(text, segments)
            meaningful_text?(text) || content_like_destination?(segments)
          end

          def score_anchor(text, segments, heading_anchor, heading_text_match)
            score = 0
            score += 100 if heading_anchor
            score += 20 if heading_text_match
            score += 10 if meaningful_text?(text)
            score += 10 if content_like_destination?(segments)
            score
          end

          def heading_anchor?(anchor, heading)
            heading && anchor.ancestors.include?(heading)
          end

          def heading_text_match?(heading_text, text)
            meaningful_text?(heading_text) && heading_text == text
          end

          def heading_for(container)
            container.at_css(HEADING_SELECTOR)
          end

          def icon_only_anchor?(anchor, text)
            !meaningful_text?(text) && anchor.at_css('img, svg')
          end

          def utility_destination?(segments)
            segments.empty? || segments.any? { |segment| UTILITY_PATH_SEGMENTS.include?(segment) }
          end

          def content_like_destination?(segments)
            segments.any? do |segment|
              CONTENT_PATH_SEGMENTS.include?(segment) || segment.match?(/\A\d[\w-]*\z/)
            end
          end

          def destination_segments(destination)
            Html2rss::Url.from_absolute(destination).path_segments
          rescue ArgumentError
            []
          end

          def normalized_destination(anchor)
            href = anchor['href'].to_s.split('#').first.to_s.strip
            return if href.empty?

            Html2rss::Url.from_relative(href, base_url).to_s
          rescue ArgumentError
            nil
          end

          def meaningful_text?(text)
            text.scan(/\p{Alnum}+/).any?
          end

          def utility_text?(text)
            text.match?(/\A(about|contact|log in|login|sign up|signup|share|comments?)\b/i)
          end

          def visible_text(node)
            return '' unless node

            HtmlExtractor.extract_visible_text(node).to_s.strip
          end
        end
      end
    end
  end
end
