# frozen_string_literal: true

module Html2rss
  ##
  # Shared anti-bot/interstitial signatures used by request and auto-source flows.
  #
  # This module centralizes signature matching so request-time guards and
  # auto-source surface classification stay consistent.
  module BlockedSurface
    INTERSTITIAL_SIGNATURES = [
      {
        key: :cloudflare_interstitial,
        min_matches: 2,
        patterns: [
          %r{<title>\s*just a moment\.\.\.\s*</title>}i,
          /checking your browser before accessing/i,
          /please (?:enable|turn on) javascript and cookies/i,
          %r{cdn-cgi/challenge-platform}i,
          /cloudflare ray id/i
        ],
        message: 'Blocked surface detected: Cloudflare anti-bot interstitial page. ' \
                 'Retry with --strategy browserless, try a more specific public listing URL, ' \
                 'or run from an environment that can complete anti-bot checks.'
      }
    ].freeze

    ##
    # Returns the first matching interstitial signature for the provided body.
    #
    # @param body [String, nil] response body candidate
    # @return [Hash, nil] signature hash when matched, otherwise nil
    def self.interstitial_signature_for(body)
      normalized_body = body.to_s
      INTERSTITIAL_SIGNATURES.find { |signature| interstitial_signature_match?(normalized_body, signature) }
    end

    ##
    # @param body [String, nil] response body candidate
    # @return [Boolean] true when body matches a known interstitial signature
    def self.interstitial?(body)
      !interstitial_signature_for(body).nil?
    end

    def self.interstitial_signature_match?(body, signature)
      matches = signature.fetch(:patterns).count { |pattern| pattern.match?(body) }
      matches >= signature.fetch(:min_matches, 1)
    end
    private_class_method :interstitial_signature_match?
  end
end
