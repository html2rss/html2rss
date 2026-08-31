# frozen_string_literal: true

module Html2rss
  ##
  # Immutable value object representing the outcome of a reconnaissance operation.
  ReconResult = Data.define(
    :requested_url,
    :final_url,
    :status,
    :verdict,
    :native_feed,
    :surface_category,
    :articles_count,
    :scheme_downgrade,
    :notes,
    :redirect_chain,
    :html_bytesize
  ) do
    ##
    # @return [Boolean] whether the page is a valid scrape candidate
    def build?
      verdict == :build
    end

    ##
    # @return [Boolean] whether scraping should be deferred because native feed exists
    def defer?
      verdict == :defer
    end

    ##
    # @return [Boolean] whether the URL should be dropped (unreachable, blocked, or broken)
    def drop?
      verdict == :drop
    end

    ##
    # @return [Boolean] whether a native RSS/Atom feed was discovered
    def native_feed?
      !native_feed.nil?
    end
    alias_method :has_native_feed?, :native_feed?

    ##
    # @return [Hash{Symbol => Object}] hash representation
    def to_h # rubocop:disable Metrics/MethodLength
      {
        requested_url: requested_url.to_s,
        final_url: final_url.to_s,
        status:,
        verdict:,
        native_feed: native_feed&.to_s,
        surface_category: surface_category&.to_s,
        articles_count:,
        scheme_downgrade:,
        notes:,
        redirect_chain:,
        html_bytesize:
      }.compact
    end
  end
end
