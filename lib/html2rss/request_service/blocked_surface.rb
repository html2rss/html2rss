# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Shared anti-bot/interstitial signatures used by request and auto-source flows.
    #
    # This module centralizes signature matching so request-time guards and
    # auto-source surface classification stay consistent.
    module BlockedSurface
      # Known interstitial fingerprints used to detect blocked or anti-bot surfaces.
      INTERSTITIAL_SIGNATURES = [
        {
          key: :cloudflare_interstitial,
          min_matches: 2,
          patterns: [
            %r{<title>\s*just a moment\.\.\.\s*</title>}i,
            /checking your browser before accessing/i,
            /please (?:enable|turn on) javascript and cookies/i,
            %r{cdn-cgi/challenge-platform}i,
            /cf-challenge/i,
            /cloudflare ray id/i
          ],
          message: 'Blocked surface detected: Cloudflare anti-bot interstitial page. ' \
                   'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, ' \
                   'or run from an environment that can complete anti-bot checks.'
        },
        {
          key: :datadome_interstitial,
          min_matches: 2,
          patterns: [
            /captcha-delivery\.com/,
            /DataDome/i,
            /interstitial/i
          ],
          message: 'Blocked surface detected: DataDome anti-bot challenge page. ' \
                   'Target a direct listing URL, or scrape via a session with resolved DataDome cookies.'
        },
        {
          key: :vercel_security_checkpoint,
          min_matches: 1,
          patterns: [
            /Vercel Security Checkpoint/i,
            %r{vercel\.com/security}i,
            /checking the security/i
          ],
          message: 'Blocked surface detected: Vercel Security Checkpoint. ' \
                   'This site is a JS-rendered SPA behind Vercel edge protection. ' \
                   'Configure BOTASAURUS_SCRAPER_URL or target a direct listing URL.'
        },
        {
          key: :http_403_forbidden,
          min_matches: 2,
          patterns: [
            %r{<title>\s*403\s+forbidden\s*</title>}i,
            %r{<h1>\s*403\s+forbidden\s*</h1>}i
          ],
          message: 'Blocked surface detected: HTTP 403 Forbidden access block page. ' \
                   'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, ' \
                   'or run from an environment that is not IP-blocked.'
        }
      ].freeze

      ##
      # Returns the first matching interstitial signature for the provided body.
      #
      # @param body [String, nil] response body candidate
      # @return [Hash, nil] signature hash when matched, otherwise nil
      def self.interstitial_signature_for(body)
        normalized_body = normalize_body(body)
        INTERSTITIAL_SIGNATURES.find { |signature| interstitial_signature_match?(normalized_body, signature) }
      end

      ##
      # @param body [String, nil] response body candidate
      # @return [Boolean] true when body matches a known interstitial signature
      def self.interstitial?(body)
        !interstitial_signature_for(body).nil?
      end

      def self.interstitial_signature_match?(body, signature)
        min_matches = signature[:min_matches]
        matches = 0

        signature[:patterns].each do |pattern|
          matches += 1 if pattern.match?(body)
          return true if matches >= min_matches
        end

        false
      end
      private_class_method :interstitial_signature_match?

      def self.normalize_body(body) = body.to_s.scrub
      private_class_method :normalize_body
    end
  end
end
