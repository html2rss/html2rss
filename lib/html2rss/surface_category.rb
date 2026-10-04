# frozen_string_literal: true

module Html2rss
  SurfaceCategory = Data.define(:name)

  ##
  # Closed surface class for no-scraper / page-assessment gates.
  #
  # Construction: {AutoSource::Scraper.classify_no_scraper_surface} and {PageRecon.assess}.
  # Predicates own weak/blocked/listing-bonus decisions — do not re-list WEAK sets in Policy/Scorer.
  class SurfaceCategory
    # Surfaces that warrant listing/feed resolution (hubs / shells — not blocked).
    WEAK = Set[:high_entropy_surface, :app_shell, :unsupported_surface].freeze

    # Frozen name → instance table.
    ALL = %i[listing blocked_surface app_shell high_entropy_surface unsupported_surface]
          .to_h { |name| [name, new(name:)] }.freeze
    private_class_method :new

    ##
    # @param name [Symbol, String]
    # @return [SurfaceCategory]
    def self.[](name) = ALL.fetch(name.to_sym) { raise ArgumentError, "unknown surface category: #{name.inspect}" }

    ##
    # @return [Boolean]
    def weak? = WEAK.include?(name)

    ##
    # @return [Boolean]
    def blocked? = name == :blocked_surface

    ##
    # @return [Boolean] listing surface eligible for listing bonus
    def listing_bonus? = name == :listing

    ##
    # @return [Symbol]
    def to_sym = name

    ##
    # @return [String]
    def to_s = name.to_s
  end
end
