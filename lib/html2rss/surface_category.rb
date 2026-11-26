# frozen_string_literal: true

module Html2rss
  SurfaceCategory = Data.define(:name)

  ##
  # Closed surface class for no-scraper / page-assessment gates.
  #
  # Construction: {.classify} and {PageRecon.assess}.
  # Predicates own weak/blocked/listing-bonus decisions — do not re-list WEAK sets in Policy/Scorer.
  class SurfaceCategory
    # Surfaces that warrant listing/entry resolution (hubs / shells — not blocked).
    WEAK = Set[:high_entropy_surface, :app_shell, :unsupported_surface].freeze

    # Root markers indicating likely app-shell/client-rendered surfaces.
    APP_SHELL_ROOT_SELECTORS = '#app, #root, #__next, [data-reactroot], [ng-app], [id*="app-shell"]'
    # Maximum anchors tolerated before app-shell detection is considered unlikely.
    APP_SHELL_MAX_ANCHORS = 2
    # Minimum same-page anchors suggesting a high-entropy homepage/hub surface.
    HIGH_ENTROPY_MIN_ANCHORS = 20
    # Maximum visible text length tolerated for app-shell classification.
    APP_SHELL_MAX_VISIBLE_TEXT_LENGTH = 220

    # Operator guidance per non-listing surface (shared by no-scraper and empty-feed errors).
    MESSAGES = {
      blocked_surface: 'blocked surface likely (anti-bot or interstitial). ' \
                       'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, ' \
                       'or run from an environment that can complete anti-bot checks.',
      app_shell: 'app-shell surface detected (client-rendered page with little or no ' \
                 'server-rendered article HTML). Target a direct listing/update URL instead of a ' \
                 'homepage or shell entrypoint; a browser strategy does not add extractable markup here.',
      high_entropy_surface: 'high-entropy surface (e.g. news homepage) with few or no durable ' \
                            'article destinations after admission. Target a section, topic, or ' \
                            'listing/update URL instead of the site homepage.',
      unsupported_surface: 'unsupported extraction surface for auto mode. ' \
                           'Try a direct listing/changelog/category URL, ' \
                           'or use explicit selectors in a feed config.'
    }.freeze

    # Frozen name → instance table.
    ALL = %i[listing blocked_surface app_shell high_entropy_surface unsupported_surface]
          .to_h { |name| [name, new(name:)] }.freeze
    private_class_method :new

    ##
    # @param name [Symbol, String]
    # @return [SurfaceCategory]
    def self.[](name) = ALL.fetch(name.to_sym) { raise InvalidOption, "unknown surface category: #{name.inspect}" }

    ##
    # Classifies why scrapers could not extract from a parsed page.
    #
    # @param parsed_body [Nokogiri::HTML::Document]
    # @param body [String, nil] raw body for blocked-surface detection
    # @return [Symbol] one of {MESSAGES} keys
    def self.classify(parsed_body, body: nil)
      return :blocked_surface if blocked_surface?(parsed_body, body:)
      return :app_shell if app_shell_surface?(parsed_body)
      return :high_entropy_surface if high_entropy_surface?(parsed_body)

      :unsupported_surface
    end

    def self.blocked_surface?(parsed_body, body:)
      RequestService::BlockedSurface.interstitial?(body || parsed_body.to_html)
    end
    private_class_method :blocked_surface?

    def self.app_shell_surface?(parsed_body)
      root_marker = parsed_body.at_css(APP_SHELL_ROOT_SELECTORS)
      return false unless root_marker

      sparse_anchor_surface?(parsed_body) &&
        no_article_markers?(parsed_body) &&
        short_visible_text?(parsed_body)
    end
    private_class_method :app_shell_surface?

    def self.high_entropy_surface?(parsed_body)
      parsed_body.css('body a[href]').size >= HIGH_ENTROPY_MIN_ANCHORS
    end
    private_class_method :high_entropy_surface?

    def self.sparse_anchor_surface?(parsed_body)
      parsed_body.css('body a[href]').size <= APP_SHELL_MAX_ANCHORS
    end
    private_class_method :sparse_anchor_surface?

    def self.no_article_markers?(parsed_body)
      parsed_body.css(
        'article, main article, [itemtype*="Article"], [itemprop="articleBody"]'
      ).empty?
    end
    private_class_method :no_article_markers?

    def self.short_visible_text?(parsed_body)
      visible_text_length(parsed_body) <= APP_SHELL_MAX_VISIBLE_TEXT_LENGTH
    end
    private_class_method :short_visible_text?

    def self.visible_text_length(parsed_body)
      text_nodes = parsed_body.xpath('//body//text()[not(ancestor::script or ancestor::style or ancestor::noscript)]')
      text_nodes.map(&:text).join(' ').gsub(/\s+/, ' ').strip.length
    end
    private_class_method :visible_text_length

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
