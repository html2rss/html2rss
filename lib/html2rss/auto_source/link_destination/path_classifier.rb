# frozen_string_literal: true

module Html2rss
  class AutoSource
    module LinkDestination
      # Classifies normalized destination path segments for scoring.
      class PathClassifier # rubocop:disable Metrics/ClassLength
        attr_reader :segments

        # Segment groups used to classify article, taxonomy, utility, and vanity routes, from one scope's words
        # ({Vocabulary::Scope#words}); this owns how they combine.
        # Utility = taxonomy ∪ chrome ∪ soft utility (do not re-list taxonomy tokens).
        #
        # @param scope [Vocabulary::Scope]
        # @return [Hash{Symbol => Set<String>}]
        def self.segment_sets(scope) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          soft = scope.words(:path_soft_utility) # excluded from high-confidence junk (still utility_path)
          # Listing words: a path ending in one is a section index, not an article.
          section = scope.words(:path_section)
          # People pages. `team` and `people` are left out on purpose: they name sports teams and
          # newsmakers in article paths. The words are unambiguous byline/staff words.
          profile = scope.words(:path_profile)
          # Editorial-office and contributor words: their child pages are often editorial notes with a
          # three-word slug, so only a one- or two-word name slug marks a profile.
          office = scope.words(:path_office)
          taxonomy = scope.words(:path_taxonomy)
          utility = taxonomy | scope.words(:path_chrome) | Vocabulary::NonTranslated::PATH | soft
          {
            content: section | scope.words(:path_article),
            section:,
            utility:,
            high_confidence_junk: utility - soft,
            taxonomy:,
            # Destinations that are never articles: games, horoscopes, quizzes, obituaries, livestreams, players.
            non_article: scope.words(:path_non_article),
            profile:,
            office:,
            people_index: profile | office,
            vanity: scope.words(:path_vanity),
            # Audio and video destinations: players, podcast episodes and recorded briefings, not text articles.
            media: scope.words(:path_media),
            deep_post_context: scope.words(:path_deep_post_context)
          }
        end
        private_class_method :segment_sets

        # The sets of every scope, frozen and interned by content: a scope that adds no ambiguous word to a
        # set (or to any set) holds the identical shared object, so only what differs is retained.
        SEGMENT_SETS_BY_SCOPE = begin
          sets = {}
          tables = {}
          Vocabulary::SCOPES.transform_values do |scope|
            table = segment_sets(scope).transform_values { |set| sets[set.freeze] ||= set }.freeze
            tables[table] ||= table
          end.freeze
        end
        # Routing shape: any digit-led slug or id (4+ digits), not a calendar year; see ArticleRules::UrlDate::YEAR.
        YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
        # Hyphenated slug shape common to article permalinks.
        POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i
        # Multi-label host mistaken for a path segment (affiliate/outlink chrome).
        # Final label must be alphabetic (TLD-like); exclude common file extensions.
        HOST_SHAPED_SEGMENT = /\A(?:www\.)?(?:[\w-]+\.)+[a-z]{2,24}\z/i
        # Common file-extension suffixes excluded from host-shaped junk matching.
        # Video files: a path ending in one is a media asset, never an article. Audio stays out (podcast items
        # link their enclosure) and so do images (`/assets/image.jpg` is pinned as not junk).
        MEDIA_FILE_EXTENSIONS = %w[mp4 webm flv mov m4v].freeze
        # All file-extension suffixes, media included (single owner of the list).
        FILE_EXTENSIONS = (%w[pdf jpe?g png gif svg webp css js mjs html? xml json zip
                              gz] + MEDIA_FILE_EXTENSIONS).freeze
        # Segment ending in a known file extension.
        FILE_EXTENSION_SEGMENT = /\.(?:#{FILE_EXTENSIONS.join('|')})\z/i
        # Segment ending in a video file extension.
        MEDIA_FILE_SEGMENT = /\.(?:#{MEDIA_FILE_EXTENSIONS.join('|')})\z/i
        # Document-style permalink: four or more words, then a numeric id of 5+ digits and a page extension
        # (`/author/the-long-title_b_4421799.html`). A text-only slug is too common on product, forum and wiki pages.
        DOCUMENT_SLUG_SEGMENT = /\A[\p{L}\d]+(?:[-_][\p{L}\d]+){3,}[-_]\d{5,}\.(?:html?|shtml|aspx?|php)\z/i

        # A single person-name slug: letters only (dated and id slugs carry digits), up to three words.
        NAME_SLUG = /\A\p{L}+(?:-\p{L}+){0,2}\z/
        # Name slug of at most two words, for office/contributor sections whose notes carry longer slugs.
        SHORT_NAME_SLUG = /\A\p{L}+(?:-\p{L}+)?\z/
        # Name-slug shape that marks a profile page, by the word set of its parent segment.
        NAME_SLUG_BY_OWNER = { profile: NAME_SLUG, office: SHORT_NAME_SLUG }.freeze

        # Pop-up / embedded player segments such as `popup-audio-player` (hyphens removed before matching).
        PLAYER_SEGMENT = /\A(?:(?:pop(?:up|out)|embed|audio|video|media)\w*)?player\z/

        # @param segments [Array<String>] normalized URL path segments
        # @param host_label [String, nil] first host label (e.g. an obituary subdomain)
        # @param query [Boolean] whether the URL carries a query string (`/blog?p=12` selects one post)
        # @param vocabulary [Vocabulary::Scope] the page language's scope; every ambiguous word by default
        def initialize(segments, host_label: nil, query: false, vocabulary: Vocabulary[nil])
          @segments = segments
          @sets = SEGMENT_SETS_BY_SCOPE.fetch(vocabulary.code)
          @query = query
          @host_label = host_label.to_s.downcase
          @lexicon = segments.map { ::Html2rss::Html::Probe.fold(_1) }.freeze
        end

        # @return [Boolean] true when the route has article-like path evidence
        def content_path?
          @content_path ||= !leading_high_confidence_junk? &&
                            (@sets[:content].intersect?(@lexicon) || yearish_content_context?)
        end

        # @return [Boolean] true when the route includes utility/navigation evidence
        def utility_path?
          @utility_path ||= @sets[:utility].intersect?(@lexicon)
        end

        # @return [Boolean] true when the route points at conversion or account chrome
        def vanity_path?
          @vanity_path ||= @sets[:vanity].intersect?(@lexicon)
        end

        # @return [Boolean] true when a path segment names an audio or video destination
        def media_path?
          @media_path ||= @sets[:media].intersect?(@lexicon)
        end

        # @return [Boolean] true when the route points at taxonomy/listing chrome
        def taxonomy_path?
          @taxonomy_path ||= @sets[:taxonomy].intersect?(@lexicon)
        end

        # @return [Boolean] true when the route is too shallow to strongly indicate an article
        def shallow?
          segment_count = segments.size

          segment_count <= 1 || (segment_count == 2 && high_confidence_junk_at?(1))
        end

        # @return [Boolean] true when the final path segment looks like a post slug
        def strong_post_suffix?
          @strong_post_suffix ||= segments.any? &&
                                  ((slug_last_segment? && trusted_post_context?(segments.size - 1)) ||
                                   document_slug_route?)
        end

        # @return [Boolean] true when every path segment is utility chrome
        def utility_only_route?
          (0...segments.size).all? { |i| high_confidence_junk_at?(i) }
        end

        # @return [Boolean] true when the route is shallow and names a soft vanity segment
        def shallow_vanity_route?
          shallow? && @lexicon.any? { |folded| @sets.fetch(:vanity).include?(folded) }
        end

        # @return [Boolean] true when the leading segments are all utility chrome
        def deep_utility_context_route?
          all_junk?(segments.size - 1)
        end

        # @return [Boolean] true when the host or a path segment names a game, horoscope, quiz,
        #   obituary, livestream or player destination, or the path is a bare section index
        def non_article_path?
          return @non_article_path if defined?(@non_article_path)

          @non_article_path = section_index? || profile_route? || media_file_route? ||
                              (!strong_post_suffix? && non_article_word_present?)
        end

        # @return [Boolean] true when the route is shallow and contains high-confidence noise
        def junk_path?
          return true if non_article_path?
          return false if excluded_content_route?

          any_high_confidence_junk_segment? || shallow_vanity_route?
        end

        # @return [Boolean] true when the route points at conversion or account chrome
        def utility_destination?
          return true if non_article_path?
          return false if excluded_content_route?

          vanity_path? || utility_route?
        end

        private

        def non_article_word_present?
          ([@host_label] + @lexicon).any? { non_article_word?(_1) }
        end

        def non_article_word?(word)
          joined = word.delete('-_')
          @sets[:non_article].include?(joined) || joined.match?(PLAYER_SEGMENT)
        end

        def media_file_route?
          segments.any? && segments.last.match?(MEDIA_FILE_SEGMENT)
        end

        # A people word that ends the path (an index) or is followed by one name slug (a profile page).
        def profile_route?
          return false if segments.empty?

          @sets[:people_index].include?(@lexicon.last) || profile_page?
        end

        def profile_page?
          return false if segments.size < 2

          NAME_SLUG_BY_OWNER.any? { |set, slug| @sets[set].include?(@lexicon[-2]) && segments.last.match?(slug) }
        end

        # A path ending in a section word (no slug) lists articles instead of being one.
        def section_index?
          !@query && segments.any? && @sets[:section].include?(@lexicon.last)
        end

        def leading_high_confidence_junk?
          segments.any? && high_confidence_junk_at?(0)
        end

        def any_high_confidence_junk_segment?
          (0...segments.size).any? { |i| high_confidence_junk_at?(i) }
        end

        def yearish_content_context?
          segments.any? { |segment| segment.match?(YEARISH_SEGMENT) } && trusted_post_context?(segments.size - 1)
        end

        def excluded_content_route?
          segments.empty? || content_path? || strong_post_suffix?
        end

        def utility_route?
          taxonomy_path? ||
            utility_only_route? ||
            deep_utility_context_route? ||
            shallow_utility_route?
        end

        def shallow_utility_route?
          shallow? && utility_path?
        end

        def all_junk?(limit)
          return false if limit <= 0

          (0...limit).all? { |i| high_confidence_junk_at?(i) }
        end

        def high_confidence_junk_at?(index)
          @sets.fetch(:high_confidence_junk).include?(@lexicon[index]) ||
            host_shaped_segment?(segments[index])
        end

        def host_shaped_segment?(segment)
          segment.match?(HOST_SHAPED_SEGMENT) && !segment.match?(FILE_EXTENSION_SEGMENT)
        end

        def trusted_post_context?(limit)
          return false if leading_high_confidence_junk?

          content = @sets.fetch(:content)
          context = @sets.fetch(:deep_post_context)
          segments.zip(@lexicon).first(limit.clamp(0..)).any? do |segment, folded|
            content.include?(folded) || segment.match?(YEARISH_SEGMENT) || context.include?(folded)
          end
        end

        # A document slug needs no content/year context, unless a slug word is utility chrome or the path names a
        # non-article destination (games, quiz, ...).
        def document_slug_route?
          return false if segments.size < 2 || leading_high_confidence_junk? || non_article_word_present?

          last = segments.last
          utility = @sets.fetch(:utility) # vanity words are a subset of utility
          # A match holds the literal dot of its extension, so a dotless slug skips the backtracking regexp.
          last.include?('.') && last.match?(DOCUMENT_SLUG_SEGMENT) &&
            last.split(/[-_.]/).none? { utility.include?(_1.downcase) }
        end

        def slug_last_segment?
          last = segments.last
          last.match?(YEARISH_SEGMENT) || last.match?(POST_SLUG_SEGMENT)
        end
      end
    end
  end
end
