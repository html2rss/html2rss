# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scoring
      ##
      # Resolves href strings into memoized LinkDestination::DestinationFacts for one page base URL and one
      # page language ({Vocabulary::Scope}). The memo lives and dies with the page, so it never holds facts of
      # another language.
      class LinkResolver
        # Captures the href portion before a fragment for memoization keys.
        HREF_BASE_PATTERN = /\A([^#]*)/

        # Matches content-like tokens in class/id strings (from {Vocabulary::CssTokens}).
        CONTENT_TOKEN_REGEXP = begin
          words = Vocabulary::CssTokens::CONTENT
          /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
        end.freeze

        # Matches utility/junk tokens in class/id strings (from {Vocabulary::CssTokens}).
        JUNK_TOKEN_REGEXP = begin
          words = Vocabulary::CssTokens::JUNK
          /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
        end.freeze

        # @param base_url [String, Html2rss::Url]
        # @param vocabulary [Vocabulary::Scope] the page language's scope; every ambiguous term by default
        def initialize(base_url, vocabulary: Vocabulary[nil])
          @base_url = base_url
          @vocabulary = vocabulary
          @by_href = {}
          @text_classifier = LinkDestination::TextClassifier.new(memoize: true, vocabulary:)
        end

        # @return [LinkDestination::TextClassifier]
        attr_reader :text_classifier

        # @return [Vocabulary::Scope] the page language's scope
        attr_reader :vocabulary

        ##
        # @param node_or_href [Html::SST::Node, String, #to_s]
        # @return [LinkDestination::DestinationFacts, nil]
        def destination_facts(node_or_href)
          href = extract_href(node_or_href)
          return unless href

          @by_href[href] ||= build_facts(href)
        rescue Html2rss::Url::InvalidUrlError
          nil
        end

        ##
        # The page's one route-facts memo ({#destination_facts} shares it): facts of an already resolved URL.
        #
        # @param url [Html2rss::Url] an absolute, normalized URL
        # @return [LinkDestination::DestinationFacts]
        def facts_for(url)
          @by_href[url.to_s] ||= LinkDestination::DestinationFacts.build(url, vocabulary: @vocabulary)
        end

        ##
        # @param text [String, #to_s]
        # @return [Boolean]
        def utility_text?(text) = @text_classifier.utility?(text)

        ##
        # @param text [String, #to_s]
        # @return [Boolean] true when the text is a short whole utility label or a sentence-form call to action,
        #   not a headline opening with a utility word
        def utility_chrome_text?(text) = @text_classifier.utility_chrome?(text)

        ##
        # @param text [String, #to_s]
        # @return [Boolean] true when only the page-only language reads the text as utility chrome
        def page_only_chrome_text?(text) = @text_classifier.page_only_chrome?(text)

        ##
        # @param text [String, #to_s]
        # @return [Boolean]
        def utility_prefix_text?(text) = @text_classifier.utility_prefix?(text)

        ##
        # @param text [String, #to_s]
        # @return [Boolean]
        def recommended_text?(text) = @text_classifier.recommended?(text)

        ##
        # @param text [String, #to_s]
        # @return [Boolean] true when the text is a list-level "more" or "see all" term of a page-only language
        def list_more_text?(text) = @text_classifier.list_more?(text)

        private

        def extract_href(node_or_href)
          raw = case node_or_href
                when Html::SST::Node then node_or_href.attrs.href
                else node_or_href
                end
          return unless raw

          base = raw.to_s[HREF_BASE_PATTERN, 1].to_s.strip
          base unless base.empty?
        end

        def build_facts(href)
          facts_for(Html2rss::Url.from_relative(href, @base_url))
        end
      end
    end
  end
end
