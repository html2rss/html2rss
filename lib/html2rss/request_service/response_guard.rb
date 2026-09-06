# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Enforces response-size limits before parsing.
    class ResponseGuard
      ##
      # @param policy [Policy] request policy that defines byte ceilings
      def initialize(policy:)
        @policy = policy
      end

      ##
      # Validates the final response body after middleware processing.
      #
      # @param body [String, nil] final response body
      # @return [void]
      # @raise [ResponseTooLarge] if the final body exceeds configured limits
      # @raise [BlockedSurfaceDetected] if the body matches known anti-bot interstitial signatures
      def inspect_body!(body)
        normalized_body = body.to_s
        size = normalized_body.bytesize
        raise_if_too_large!(size, policy.max_decompressed_bytes)
        raise_if_blocked_surface!(normalized_body)
      end

      private

      attr_reader :policy

      def raise_if_blocked_surface!(body)
        signature = BlockedSurface.interstitial_signature_for(body)
        return unless signature

        raise BlockedSurfaceDetected, signature.fetch(:message)
      end

      def raise_if_too_large!(bytes, limit)
        return unless bytes > limit

        raise ResponseTooLarge, "Response exceeded #{limit} bytes"
      end
    end
  end
end
