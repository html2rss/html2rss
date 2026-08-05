# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Shared link eligibility and scoring policy for AutoSource scrapers.
      #
      # Scrapers collect DOM observations; this module owns junk/noise rules and
      # numeric weights so eligibility policy stays in one place.
      class LinkHeuristics # rubocop:disable Metrics/ClassLength
        # Score weights keyed by AnchorSignals member name.
        ANCHOR_SCORE_RULES = {
          heading_anchor: 100,
          heading_text_match: 20,
          meaningful_text: 10,
          content_like_destination: 10
        }.freeze

        # Anchor ranking signals used by semantic primary-link selection.
        AnchorSignals = Data.define(
          :heading_anchor,
          :heading_text_match,
          :meaningful_text,
          :content_like_destination
        ) do
          # @return [Integer] ranking score for one eligible anchor
          def score
            ANCHOR_SCORE_RULES.sum { |signal, weight| public_send(signal) ? weight : 0 }
          end
        end

        # Container observations used to compute quality/junk scores.
        ContainerSignals = Data.define(
          :title_word_count,
          :path_length,
          :content_path,
          :publish_marker,
          :descriptive_context,
          :article_container,
          :content_tokens,
          :junk_tokens,
          :utility_prefix_title,
          :recommended_title,
          :utility_path,
          :strong_post_suffix,
          :shallow,
          :high_confidence_junk_path,
          :high_confidence_utility_destination,
          :selected_anchor_present
        ) do
          # @return [Integer] positive quality contribution for ranking
          def quality_score # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            score = 0
            score += 40 if title_word_count >= 3
            score += 15 if title_word_count >= 7
            score += 20 if path_length > 6
            score += 15 if content_path
            score += 15 if publish_marker
            score += 10 if descriptive_context
            score += 10 if article_container
            score += 10 if content_tokens
            score
          end

          # @return [Integer] junk penalty subtracted from quality
          def junk_score # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            score = 0
            score += 25 if non_content_utility_path?
            score += 15 if utility_prefix_title && title_word_count <= 6
            score += 10 if shallow
            score += 10 if weak_container?
            score += 10 if recommended_title && !content_path
            score += 5 if high_confidence_junk_path
            score += 15 if junk_tokens
            score
          end

          # @return [Integer] quality minus junk for stable ranking
          def final_score = quality_score - junk_score

          # @return [Boolean] true when the entry should be dropped before ranking
          def hard_junk? # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            weak = weak_article_candidate?

            high_confidence_junk_path ||
              (selected_anchor_present && recommended_title && shallow && weak) ||
              (selected_anchor_present && utility_prefix_title &&
                high_confidence_utility_destination && weak)
          end

          private

          # @return [Boolean] true when article evidence is too weak to keep
          def weak_article_candidate?
            [article_container, publish_marker, descriptive_context, content_path].count(&:itself) < 2
          end

          def non_content_utility_path?
            utility_path && !content_path && !strong_post_suffix
          end

          def weak_container? = !publish_marker && !descriptive_context
        end

        # Normalized URL plus reusable route-classification facts for one link.
        DestinationFacts = Data.define(
          :url,
          :destination,
          :segments,
          :content_path,
          :utility_path,
          :taxonomy_path,
          :vanity_path,
          :shallow,
          :strong_post_suffix,
          :high_confidence_junk_path,
          :high_confidence_utility_destination
        ) do
          # @param url [Html2rss::Url] normalized destination URL
          # @return [DestinationFacts] route facts for downstream link scoring
          def self.build(url) # rubocop:disable Metrics/MethodLength
            classifier = PathClassifier.new(url.path_segments)

            new(
              url:,
              destination: url.to_s,
              segments: classifier.segments,
              strong_post_suffix: classifier.strong_post_suffix?,
              content_path: classifier.content_path?,
              utility_path: classifier.utility_path?,
              taxonomy_path: classifier.taxonomy_path?,
              vanity_path: classifier.vanity_path?,
              shallow: classifier.shallow?,
              high_confidence_junk_path: classifier.junk_path?,
              high_confidence_utility_destination: classifier.utility_destination?
            )
          end
        end

        # Extracts a normalized href from a Nokogiri anchor or raw href value.
        class HrefExtractor
          # Regexp to capture everything before the first '#'
          HREF_BASE_PATTERN = /\A([^#]*)/

          # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
          # @return [String, nil] href without fragment, or nil when blank
          def self.call(anchor_or_href) = new(anchor_or_href).call

          # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
          def initialize(anchor_or_href)
            @anchor_or_href = anchor_or_href
          end

          # @return [String, nil] href without fragment, or nil when blank
          def call
            href = case @anchor_or_href
                   when Nokogiri::XML::Node
                     @anchor_or_href['href']
                   else
                     @anchor_or_href
                   end

            return unless href

            # Extract base part before # and strip whitespace
            base = href.to_s[HREF_BASE_PATTERN, 1].strip
            base unless base.empty?
          end
        end

        # Classifies visible anchor text for utility and recommendation chrome.
        class TextClassifier
          # Prefix labels that usually identify navigation or subscription links.
          UTILITY_PREFIX_PATTERN = /
            \A\s*(
              # English
              view\s+all|see\s+all|all\s+news|subscribe|newsletter|comment\s+feed|comments\s+feed|join|premium|plus|
              # German
              alle\s+anzeigen|alle\s+news|abonnieren|newsletter|kommentar\s+feed|mitmachen|
              # Spanish
              ver\s+todos|ver\s+todo|todas\s+las\s+noticias|suscribirse|bolet(i|í)n|comentarios\s+feed|unirse|
              # French
              voir\s+tout|voir\s+tous|toutes\s+les\s+nouvelles|s['’]abonner|flux\s+de\s+commentaires|rejoindre
            )\b
          /ix
          # Short labels that usually identify non-article navigation links.
          UTILITY_PATTERN = /
            \A\s*(
              # English
              about|contact|comments?|join|log\s+in|login|member(ship)?|
              plus|premium|pricing|recommended(\s+for\s+you)?|
              see\s+all|share|sign\s+up|signup|subscribe|view\s+all|
              # German
              (ue|ü)ber(\s+uns)?|kontakt|kommentare?|mitmachen|anmelden|login|
              mitglied(schaft)?|empfohlen(\s+f(ue|ü)r\s+dich)?|alle\s+anzeigen|
              teilen|registrieren|abonnieren|newsletter|
              # Spanish
              sobre(\s+nosotros)?|contacto|comentarios?|unirse|iniciar\s+sesion|
              login|miembro|membres(i|í)a|recomendado(\s+para\s+ti)?|ver\s+todo|
              compartir|registrarse|suscribirse|bolet(i|í)n|
              # French
              (a|à)\s+propos|(a|à)propos|contact|commentaires?|rejoindre|
              se\s+connecter|login|membre|abonnement|recommand(e|é)(\s+pour\s+vous)?|
              voir\s+tout|partager|s['’]inscrire|s['’]abonner|newsletter
            )\b
          /ix
          # Labels for recommendation chrome rather than source articles.
          RECOMMENDED_PATTERN = /
            \A\s*(
              recommended(\s+for\s+you)?|
              empfohlen(\s+f(ue|ü)r\s+dich)?|
              recomendado(\s+para\s+ti)?|
              recommand(e|é)(\s+pour\s+vous)?
            )\b
          /ix

          # @param text [String, #to_s] visible anchor text
          # @return [Boolean] true when text matches a utility label
          def utility?(text) = text.to_s.match?(UTILITY_PATTERN)

          # @param text [String, #to_s] visible anchor text
          # @return [Boolean] true when text begins with a utility label
          def utility_prefix?(text) = text.to_s.match?(UTILITY_PREFIX_PATTERN)

          # @param text [String, #to_s] visible anchor text
          # @return [Boolean] true when text identifies recommendation chrome
          def recommended?(text) = text.to_s.match?(RECOMMENDED_PATTERN)
        end

        # Classifies normalized destination path segments for scoring.
        class PathClassifier # rubocop:disable Metrics/ClassLength
          attr_reader :segments

          # Segment groups used to classify article, taxonomy, utility, and vanity routes.
          SEGMENT_SETS = {
            content: %w[
              article articles blog blogs changelog changelogs insight insights
              launch launches news post posts release releases story stories update updates
              artikel beitrag beitraege nachrichten neuigkeiten aktuelles
              articulo articulos noticia noticias entrada entradas publicacion publicaciones
              actualite actualites nouvelle nouvelles
              teaser teasers card cards
            ].to_set.freeze,
            utility: %w[
              about account archive archives author authors category categories comment comments
              contact feedback help login logout newsletter newsletters notification notifications
              preference preferences profile register search settings share signup subscribe
              tag tags topic topics
              feed feeds comment-feed comments-feed
              recommended
              for-you
              privacy terms cookie cookies
              join member members membership plus premium plans pricing user users
              kategorie kategorien schlagwort schlagworte thema themen autor autoren archiv
              ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
              konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
              categoria categorias etiqueta etiquetas tema temas autores archivos
              sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar
              registrarse registro cuenta suscribirse boletin privacidad condiciones
              categorie etiquette etiquettes sujet sujets theme themes auteur auteurs
              a-propos apropos recherche rechercher aide connexion s-inscrire
              sinscrire inscription compte s-abonner saboner lettre-information confidentialite mentions-legales cgu
              menu sidebar widget social modal popup banner promo ad ads
              related recommendation recommendations pagination pager
            ].to_set.freeze,
            high_confidence_junk: %w[
              about account archive archives author authors category categories comment comments
              contact cookie cookies feedback feed feeds help login logout notification notifications
              preference preferences privacy profile register search settings share signup subscribe
              tag tags terms topic topics comment-feed comments-feed user users
              kategorie kategorien schlagwort schlagworte thema themen autor autoren archiv
              ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
              konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
              categoria categorias etiqueta etiquetas tema temas autores archivos
              sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar
              registrarse registro cuenta suscribirse boletin privacidad condiciones
              categorie etiquette etiquettes sujet sujets theme themes auteur auteurs
              a-propos apropos recherche rechercher aide connexion s-inscrire
              sinscrire inscription compte s-abonner saboner lettre-information confidentialite mentions-legales cgu
              menu sidebar widget social modal popup banner promo ad ads
              related recommendation recommendations pagination pager
            ].to_set.freeze,
            taxonomy: %w[
              category categories tag tags topic topics
              kategorie kategorien schlagwort schlagworte thema themen
              categoria categorias etiqueta etiquetas tema temas
              categorie etiquette etiquettes sujet sujets theme themes
            ].to_set.freeze,
            vanity: %w[
              join membership plus premium pricing plans subscribe signup
              abonnieren abo
              suscribirse boletin
              s-abonner saboner
            ].to_set.freeze,
            deep_post_context: %w[
              press newsroom
              presse pressemitteilungen
              prensa
            ].to_set.freeze
          }.freeze
          # Path segment that begins with a year-like publishing marker.
          YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
          # Hyphenated slug shape common to article permalinks.
          POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i

          # @param segments [Array<String>] normalized URL path segments
          def initialize(segments)
            @segments = segments
          end

          # @return [Boolean] true when the route has article-like path evidence
          def content_path?
            @content_path ||= SEGMENT_SETS[:content].intersect?(segments) ||
                              yearish_content_context?
          end

          # @return [Boolean] true when the route includes utility/navigation evidence
          def utility_path?
            @utility_path ||= SEGMENT_SETS[:utility].intersect?(segments)
          end

          # @return [Boolean] true when the route points at conversion or account chrome
          def vanity_path?
            @vanity_path ||= SEGMENT_SETS[:vanity].intersect?(segments)
          end

          # @return [Boolean] true when the route points at taxonomy/listing chrome
          def taxonomy_path?
            @taxonomy_path ||= SEGMENT_SETS[:taxonomy].intersect?(segments)
          end

          # @return [Boolean] true when the route is too shallow to strongly indicate an article
          def shallow?
            segment_count = segments.size
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)

            segment_count <= 1 || (segment_count == 2 && junk_segments.include?(segments.last))
          end

          # @return [Boolean] true when the final path segment looks like a post slug
          def strong_post_suffix?
            @strong_post_suffix ||= segments.any? &&
                                    included_last_segment? &&
                                    trusted_post_context?(segments.size - 1)
          end

          # @return [Boolean] true when every path segment is utility chrome
          def utility_only_route?
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)

            segments.all? { |segment| junk_segments.include?(segment) }
          end

          # @return [Boolean] true when the route is shallow and contains high-confidence noise
          def shallow_high_confidence_route?
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)
            vanity_segments = SEGMENT_SETS.fetch(:vanity)

            shallow? && segments.any? do |segment|
              junk_segments.include?(segment) || vanity_segments.include?(segment)
            end
          end

          # @return [Boolean] true when the leading segments are all utility chrome
          def deep_utility_context_route?
            all_junk?(segments.size - 1)
          end

          # @return [Boolean] true when the route is shallow and contains high-confidence noise
          def junk_path?
            return false if excluded_content_route?

            taxonomy_path? ||
              utility_only_route? ||
              deep_utility_context_route? ||
              shallow_high_confidence_route?
          end

          # @return [Boolean] true when the route points at conversion or account chrome
          def utility_destination?
            return false if excluded_content_route?

            vanity_path? || utility_route?
          end

          private

          def yearish_content_context?
            segments.any? { |segment| segment.match?(YEARISH_SEGMENT) } &&
              (strong_post_suffix? || trusted_post_context?(segments.size - 1))
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

            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)
            (0...limit).all? { |i| junk_segments.include?(segments[i]) }
          end

          def trusted_post_context?(limit)
            return false if limit <= 0

            content_segments = SEGMENT_SETS.fetch(:content)
            context_segments = SEGMENT_SETS.fetch(:deep_post_context)

            (0...limit).any? do |i|
              segment = segments[i]
              content_segments.include?(segment) ||
                segment.match?(PathClassifier::YEARISH_SEGMENT) ||
                context_segments.include?(segment)
            end
          end

          def included_last_segment?
            !excluded_last_segment? && slug_last_segment?
          end

          def excluded_last_segment?
            last = segments.last
            [SEGMENT_SETS[:high_confidence_junk], SEGMENT_SETS[:vanity]].any? { |set| set.include?(last) }
          end

          def slug_last_segment?
            last = segments.last
            last.match?(YEARISH_SEGMENT) || last.match?(POST_SLUG_SEGMENT)
          end
        end

        # @param base_url [String, Html2rss::Url] page URL used to resolve relative hrefs
        def initialize(base_url)
          @base_url = base_url
          @text_classifier = TextClassifier.new
          @container_assessor = ContainerAssessor.new(text_classifier: @text_classifier)
        end

        # Builds normalized destination facts for an anchor element or href string.
        #
        # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
        # @return [DestinationFacts, nil] normalized destination facts, or nil for blank/invalid URLs
        def destination_facts(anchor_or_href)
          return node_facts[anchor_or_href] if node_facts.key?(anchor_or_href)

          href = HrefExtractor.call(anchor_or_href)
          return unless href

          res = memoized_destination_facts(href)

          node_facts[anchor_or_href] = res if anchor_or_href.is_a?(Nokogiri::XML::Node)
          res
        rescue ArgumentError
          nil
        end

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text matches a utility label
        def utility_text?(text) = @text_classifier.utility?(text)

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text begins with a utility label
        def utility_prefix_text?(text) = @text_classifier.utility_prefix?(text)

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text identifies recommendation chrome
        def recommended_text?(text) = @text_classifier.recommended?(text)

        ##
        # Whether an anchor is junk chrome rather than a content permalink.
        #
        # Policy lives here so Html / SemanticHtml scrapers do not reimplement
        # taxonomy/utility/recommended noise rules.
        #
        # @param text [String, #to_s] visible anchor text
        # @param destination_facts [DestinationFacts, nil] route facts for the href
        # @return [Boolean] true when the anchor should be ignored
        def noise_anchor?(text:, destination_facts:) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          return true unless destination_facts

          destination_facts.taxonomy_path ||
            short_utility_label?(text, destination_facts) ||
            (recommended_text?(text) && destination_facts.shallow) ||
            (utility_prefix_text?(text) && destination_facts.high_confidence_utility_destination) ||
            (utility_text?(text) && destination_facts.vanity_path)
        end

        ##
        # Observes a container and builds ranking signals, including hard-junk.
        #
        # Delegates DOM observation to ContainerAssessor so SemanticHtml only
        # orchestrates candidates and extraction, while ContainerSignals keeps
        # scoring policy.
        #
        # @param container [Nokogiri::XML::Node] semantic container node
        # @param selected_anchor [Nokogiri::XML::Node, nil] primary anchor for the container
        # @param destination_facts [DestinationFacts, nil] route facts for the selected anchor
        # @return [ContainerSignals] observation + scoring signals for the container
        def assess_container(container, selected_anchor, destination_facts:)
          @container_assessor.call(container, selected_anchor, destination_facts:)
        end

        private

        def short_utility_label?(text, destination_facts)
          destination_facts.utility_path &&
            !destination_facts.content_path &&
            !destination_facts.strong_post_suffix &&
            text.to_s.scan(/\p{Alnum}+/).size <= 3
        end

        def node_facts
          @node_facts ||= {}.compare_by_identity
        end

        def memoized_destination_facts(href)
          (@destination_facts ||= {})[href] ||= begin
            url = Html2rss::Url.from_relative(href, @base_url)
            DestinationFacts.build(url)
          end
        end
      end
    end
  end
end
