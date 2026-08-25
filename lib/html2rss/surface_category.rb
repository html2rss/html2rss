# frozen_string_literal: true

module Html2rss
  ##
  # Closed surface class for no-scraper / page-assessment gates.
  #
  # Construction: {AutoSource::Scraper.classify_no_scraper_surface} and {PageRecon.assess}.
  # Predicates own weak/blocked/listing-bonus decisions — do not re-list WEAK sets in Policy/Scorer.
  class SurfaceCategory
    # Surfaces that warrant listing/feed resolution (hubs / shells — not blocked).
    WEAK = Set[:high_entropy_surface, :app_shell, :unsupported_surface].freeze

    class << self
      ##
      # @param value [SurfaceCategory, Symbol, String, nil]
      # @return [SurfaceCategory]
      def coerce(value)
        return value if value.is_a?(self)
        return new(name: nil) if value.nil?

        new(name: value.to_sym)
      end
    end

    ##
    # @return [Symbol, nil]
    attr_reader :name

    ##
    # @param name [Symbol, nil]
    def initialize(name:)
      @name = name
    end

    ##
    # @return [Boolean]
    def weak? = WEAK.include?(name)

    ##
    # @return [Boolean]
    def blocked? = name == :blocked_surface

    ##
    # @return [Boolean] non-weak, non-blocked surface eligible for listing bonus
    def listing_bonus? = !name.nil? && !weak? && !blocked?

    ##
    # @return [Symbol, nil]
    def to_sym = name

    ##
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(self.class) && name == other.name
    end
    alias eql? ==

    ##
    # @return [Integer]
    def hash = [self.class, name].hash
  end
end
