# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # The query params a page uses to place links, not to name articles: owner of the evidence rule.
      # {PageLinks} computes the set once per page and keys every consumer on it ({PageLinks#identity}).
      #
      # A param is placement-only on a page when the page's content links show both:
      #
      # - it appears on at least {MIN_PATHS} distinct paths, so it is a site convention, not one script's
      #   argument (+/news.php?id=1+ and +/news.php?id=2+ are two articles of one path); and
      # - at least {MIN_REPEATED_PATHS} of those paths appear under two or more values of it while every
      #   other query pair stays equal: the same story linked from several slots (+?pos=top+, +?pos=latest+).
      #
      # No param name is listed; the page decides.
      class PlacementParams
        # Fewest distinct paths that must carry a param before it can be a page-wide convention.
        MIN_PATHS = 3
        # Fewest of those paths that must appear under two or more of its values, all else equal.
        MIN_REPEATED_PATHS = 1

        class << self
          ##
          # @param urls [Array<Html2rss::Url>] the page's content link URLs
          # @return [Set<String>] names of the placement-only params; empty when the page shows none
          def names(urls)
            by_param = Hash.new { |params, name| params[name] = Hash.new { |stories, key| stories[key] = Set.new } }
            urls.each { record(by_param, _1) }
            by_param.select { |_name, by_story| placement?(by_story) }.keys.to_set.freeze
          end

          private

          # Files each +key=value+ pair of +url+ under its name, then under its path and other pairs (a story).
          def record(by_param, url)
            params = url.article_params
            params.each { by_param[_1.partition('=').first][[url.article_location, params - [_1]]] << _1 }
          end

          # @param by_story [Hash{Array => Set<String>}] +key=value+ pairs seen per path and other-pairs combination
          def placement?(by_story)
            paths = by_story.keys.to_set(&:first)
            repeated = by_story.select { |_story, pairs| pairs.size > 1 }.keys.to_set(&:first)
            paths.size >= MIN_PATHS && repeated.size >= MIN_REPEATED_PATHS
          end
        end
      end
    end
  end
end
