# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # :reek:MissingSafeMethod { enabled: false }
    # It applies various strategies to filter and refine the article list.
    # Sole producer of admission drop tallies for {Html2rss::Status}.
    class Cleanup # rubocop:disable Metrics/ClassLength -- reject steps + tallies stay co-located
      # Default cleanup behavior for auto-sourced article lists.
      DEFAULT_CONFIG = {
        keep_different_domain: false
      }.freeze

      # Minimum alphanumeric word count for present titles.
      MIN_WORDS = 3

      # Allowed URL schemes for article filtering.
      VALID_SCHEMES = %w[http https].to_set.freeze

      # Photo-credit agencies (single list → junk title regexes).
      CREDIT_AGENCIES = [
        'AFP',
        'Getty(?:\s+Images)?',
        'Reuters',
        'dpa',
        'Imagn'
      ].freeze
      private_constant :CREDIT_AGENCIES

      AGENCY_ALT = CREDIT_AGENCIES.join('|').freeze
      private_constant :AGENCY_ALT

      # Sole denylist for extracted titles. Order: higher-frequency reasons first.
      JUNK_TITLE_RULES = [
        [:credit, %r{\A(?:#{AGENCY_ALT})(?:\s*/\s*(?:#{AGENCY_ALT}))*\z}ix],
        [:credit, /\A(?:Image|Photo|Credit)\s*[:|]?\s*(?:#{AGENCY_ALT})\b/ix],
        [:credit, /\ACourtesy\b.+\b(?:via|pool|Handout|#{AGENCY_ALT})\b/ix],
        [:credit, /\bHandout\b.+\b(?:#{AGENCY_ALT})\b|\b(?:#{AGENCY_ALT})\b.+\bHandout\b/ix],
        [:credit, /\A(?:Live\s+Updates|Analysis)\s*[•·.:-]?\s*.*\b(?:#{AGENCY_ALT})\b/ix],
        [:cms_token, /\A(?:lucy\.\w[\w.-]*|methode[-.][\w.-]+)\z/i],
        [:slug, /\A\p{Alnum}+(?:[-_]\p{Alnum}+){2,}\z/],
        [:date_prefix, /\A\d{4}(?:[\s.-]+\d{1,2}){2}\b/],
        [:titleized_path, /\A(?:\d+|\p{Lu}[\p{L}\p{M}]*)(?:\s+(?:\d+|\p{Lu}[\p{L}\p{M}]*))*\s+\d{6,}\z/],
        [:video_chrome, /\AClipped\s+From\s+Video\b/i],
        [:video_chrome, /\AVideo\s*[•·]/i],
        [:template, /\ACreated\s+from\s+Template\s+ID\b/i],
        [:template, /(\{\{[^}]+\}\}|%\{\w+\})/]
      ].freeze
      private_constant :JUNK_TITLE_RULES

      # Admitted articles plus reason → count tallies for drops.
      Result = Data.define(:articles, :drop_tallies)

      class << self
        # @param articles [Array<Article>] extracted article candidates
        # @param url [Html2rss::Url] feed source URL used for same-host filtering
        # @param keep_different_domain [Boolean] whether to keep off-domain entries
        # @return [Result] cleaned articles and frozen drop tallies
        def call(articles, url:, keep_different_domain: DEFAULT_CONFIG.fetch(:keep_different_domain)) # rubocop:disable Metrics/MethodLength -- ordered reject pipeline
          Log.debug "Cleanup: start with #{articles.size} articles"
          tallies = Hash.new(0)

          reject_invalid!(articles, tallies)
          deduplicate_by_url!(articles, tallies)
          keep_only_http_urls!(articles, tallies)
          reject_self_links!(articles, url, tallies)
          reject_different_domain!(articles, url, tallies) unless keep_different_domain
          reject_excluded_destinations!(articles, tallies)
          reject_low_quality_titles!(articles, tallies)

          Log.debug "Cleanup: end with #{articles.size} articles"
          Result.new(articles:, drop_tallies: tallies.freeze)
        end

        # First matching junk reason for a title, or nil when the title is acceptable.
        #
        # @param title [String, nil] candidate title text
        # @return [Symbol, nil]
        def junk_reason(title)
          return if title.nil?

          normalized = normalize_title(title)
          return if normalized.empty?

          JUNK_TITLE_RULES.find { |_, pattern| pattern.match?(normalized) }&.first
        end

        private

        def reject_invalid!(articles, tallies)
          tally_reject!(articles, tallies, 'invalid') { |article| !article.valid? }
        end

        def deduplicate_by_url!(articles, tallies)
          seen = {}
          tally_reject!(articles, tallies, 'duplicate_url') do |article|
            identity = url_identity(article.url)
            identity.nil? || seen.key?(identity).tap { seen[identity] = true }
          end
        end

        def keep_only_http_urls!(articles, tallies)
          tally_reject!(articles, tallies, 'bad_scheme') do |article|
            !VALID_SCHEMES.include?(article.url&.scheme)
          end
        end

        def reject_self_links!(articles, base_url, tallies)
          source_identity = url_identity(base_url)
          tally_reject!(articles, tallies, 'self_link') do |article|
            url_identity(article.url) == source_identity
          end
        end

        def reject_different_domain!(articles, base_url, tallies)
          base_host = base_url.host
          tally_reject!(articles, tallies, 'different_domain') do |article|
            article.url&.host != base_host
          end
        end

        # Hard-exclude non-article destination classes (commerce/affiliate/utility chrome).
        # PathClassifier owns route facts; Cleanup owns feed-item admission.
        def reject_excluded_destinations!(articles, tallies)
          tally_reject!(articles, tallies, 'excluded_destination') do |article|
            excluded_destination?(article.url)
          end
        end

        def excluded_destination?(url)
          return false unless url

          facts = LinkDestination::DestinationFacts.build(url)
          return true if facts.high_confidence_junk_path || facts.high_confidence_utility_destination

          facts.utility_path && !facts.content_path && !facts.strong_post_suffix
        end

        # Keep missing titles (nil provenance). Drop present junk/unnatural titles —
        # blanking them would hide bad extraction as "unknown" and inflate empty items.
        def reject_low_quality_titles!(articles, tallies) # rubocop:disable Metrics/MethodLength -- junk vs word-count reasons
          articles.reject! do |article|
            title = article.title
            next false if title.nil?

            reason = junk_reason(title)
            if reason
              tallies[reason.to_s] += 1
              next true
            end

            next false if word_count_at_least?(title, MIN_WORDS)

            tallies['low_word_count'] += 1
            true
          end
        end

        def tally_reject!(articles, tallies, reason)
          articles.reject! do |article|
            next false unless yield(article)

            tallies[reason] += 1
            true
          end
        end

        def url_identity(url)
          url&.without_fragment&.to_s
        end

        def normalize_title(title)
          title.to_s.strip.gsub(/\s+/, ' ')
        end

        def word_count_at_least?(str, min_words)
          count = 0
          str.to_s.scan(/\p{Alnum}+/) do
            count += 1
            return true if count >= min_words
          end
          false
        end
      end
    end
  end
end
