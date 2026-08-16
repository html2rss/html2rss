# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # :reek:MissingSafeMethod { enabled: false }
    # It applies various strategies to filter and refine the article list.
    class Cleanup
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

      # Sole denylist for extracted titles (normalize once, then any?).
      JUNK_TITLE_PATTERNS = [
        %r{\A(?:#{AGENCY_ALT})(?:\s*/\s*(?:#{AGENCY_ALT}))*\z}ix,
        /\A(?:Image|Photo|Credit)\s*[:|]?\s*(?:#{AGENCY_ALT})\b/ix,
        /\ACourtesy\b/i,
        /\bHandout\b.+\b(?:#{AGENCY_ALT})\b|\b(?:#{AGENCY_ALT})\b.+\bHandout\b/ix,
        /\A(?:Live\s+Updates|Analysis)\s*[•·.:-]?\s*.*\b(?:#{AGENCY_ALT})\b/ix,
        /\A(?:lucy\.\w[\w.-]*|methode[-.][\w.-]+)\z/i,
        /\ACreated\s+from\s+Template\s+ID\b/i,
        /\AClipped\s+From\s+Video\b/i,
        /\AVideo\s*[•·.:]/i,
        /\A\p{Alnum}+(?:[-_]\p{Alnum}+){2,}\z/,
        /\A\d{4}(?:[\s.-]+\d{1,2}){2}\b/,
        /\A(?:\d+|\p{Lu}[\p{L}\p{M}]*)(?:\s+(?:\d+|\p{Lu}[\p{L}\p{M}]*))*\s+\d{6,}\z/,
        /(\{\{[^}]+\}\}|%\{\w+\})/
      ].freeze
      private_constant :JUNK_TITLE_PATTERNS

      class << self
        # @param articles [Array<Article>] extracted article candidates
        # @param url [Html2rss::Url] feed source URL used for same-host filtering
        # @param keep_different_domain [Boolean] whether to keep off-domain entries
        # @return [Array<Article>] cleaned article list
        def call(articles, url:, keep_different_domain: DEFAULT_CONFIG.fetch(:keep_different_domain))
          Log.debug "Cleanup: start with #{articles.size} articles"

          articles.select!(&:valid?)

          deduplicate_by_url!(articles)
          keep_only_http_urls!(articles)
          reject_self_links!(articles, url)
          reject_different_domain!(articles, url) unless keep_different_domain
          reject_low_quality_titles!(articles)

          Log.debug "Cleanup: end with #{articles.size} articles"
          articles
        end

        # @param title [String, nil] candidate title text
        # @return [Boolean] true when the title matches a known junk shape
        def junk_title?(title)
          return false if title.nil?

          normalized = normalize_title(title)
          return false if normalized.empty?

          JUNK_TITLE_PATTERNS.any? { |rx| rx.match?(normalized) }
        end

        private

        def deduplicate_by_url!(articles)
          seen = {}
          articles.reject! do |article|
            identity = url_identity(article.url)
            identity.nil? || seen.key?(identity).tap { seen[identity] = true }
          end
        end

        def keep_only_http_urls!(articles)
          articles.select! { |article| VALID_SCHEMES.include?(article.url&.scheme) }
        end

        def reject_self_links!(articles, base_url)
          source_identity = url_identity(base_url)
          articles.reject! { |article| url_identity(article.url) == source_identity }
        end

        def reject_different_domain!(articles, base_url)
          base_host = base_url.host
          articles.select! { |article| article.url&.host == base_host }
        end

        # Keep missing titles (nil provenance). Drop present junk/unnatural titles —
        # blanking them would hide bad extraction as "unknown" and inflate empty items.
        def reject_low_quality_titles!(articles)
          articles.select! do |article|
            title = article.title
            title.nil? || (word_count_at_least?(title, MIN_WORDS) && !junk_title?(title))
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
