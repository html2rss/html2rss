# frozen_string_literal: true

module Html2rss
  class RequestService
    class PuppetCommander
      ##
      # Owns Puppeteer request interception, deferred navigation errors, main-frame
      # filtering, and redirect-chain validation via {Policy}.
      #
      # Does not re-own Policy rules — only calls +validate_*!+ on +ctx.policy+.
      class NavigationGuards
        class << self
          ##
          # Resolves the final response URL for Response building and IP validation.
          #
          # @param navigation_response [Puppeteer::HTTPResponse, nil]
          # @param fallback_url [String, Html2rss::Url]
          # @return [Html2rss::Url]
          def response_url(navigation_response, fallback_url)
            raw_url = navigation_response&.url || fallback_url.to_s
            Html2rss::Url.from_absolute(raw_url)
          end
        end

        ##
        # @param ctx [Context] request context providing policy and origin
        # @param skip_request_resources [Set<String>] resource types to abort
        def initialize(ctx:, skip_request_resources:)
          @ctx = ctx
          @skip_request_resources = skip_request_resources
          @navigation_error = nil
          @latest_navigation_response = nil
          @main_frame = nil
        end

        ##
        # Captures the main frame and wires request/response interceptors.
        #
        # @param page [Puppeteer::Page] browser page
        # @return [void]
        def install!(page)
          @main_frame = page.main_frame if page.respond_to?(:main_frame)
          page.request_interception = true
          page.on('request') { |request| handle_request(request) }
          page.on('response') { |response| handle_response(response) }
        end

        ##
        # Clears deferred error and latest navigation response before goto.
        #
        # @return [void]
        def begin_navigation!
          @navigation_error = nil
          @latest_navigation_response = nil
        end

        ##
        # Re-raises a deferred navigation error when one was captured.
        #
        # @return [void]
        # @raise [Html2rss::Error] when a navigation request or response validation failed
        def raise_deferred_error!
          raise @navigation_error if @navigation_error
        end

        ##
        # @return [Puppeteer::HTTPResponse, nil] latest main-frame navigation response
        attr_reader :latest_navigation_response

        ##
        # Validates the remote IP of a navigation response via Policy.
        #
        # @param navigation_response [Puppeteer::HTTPResponse, nil]
        # @return [void]
        def validate_final!(navigation_response)
          final_url = self.class.response_url(navigation_response, ctx.url)
          ctx.policy.validate_remote_ip!(ip: remote_ip(navigation_response), url: final_url)
        end

        private

        attr_reader :ctx, :skip_request_resources, :main_frame

        def handle_request(request)
          validate_request!(request)

          skip_request_resources.member?(request.resource_type) ? request.abort : request.continue
        rescue Html2rss::Error => error
          store_navigation_error(error, navigation_request: request.navigation_request?)
          request.abort
        end

        def handle_response(response)
          @latest_navigation_response = response if main_frame_navigation_response?(response)
          validate_final!(response)
        rescue Html2rss::Error => error
          store_navigation_error(error, navigation_request: response.request.navigation_request?)
        end

        def validate_request!(request)
          validate_navigation_redirect_chain!(request)
          validate_navigation_target!(request)
        end

        def main_frame_navigation_response?(response)
          request = response.request
          return false unless request.navigation_request?
          return true unless request.respond_to?(:frame)

          frame = request.frame
          return true if frame.nil?
          return frame == main_frame unless main_frame.nil?
          return true unless frame.respond_to?(:parent_frame)

          frame.parent_frame.nil?
        end

        def remote_ip(navigation_response)
          navigation_response.remote_address&.ip
        end

        def request_chain(request)
          (request.redirect_chain + [request]).map { |entry| request_url(entry) }
        end

        def request_url(request)
          Html2rss::Url.from_absolute(request.url)
        end

        def validate_navigation_redirect_chain!(request)
          request_chain(request).each_cons(2) do |from_url, to_url|
            ctx.policy.validate_redirect!(from_url:, to_url:, origin_url: ctx.origin_url, relation: ctx.relation)
          end
        end

        def validate_navigation_target!(request)
          ctx.policy.validate_request!(url: request_url(request), origin_url: ctx.origin_url, relation: ctx.relation)
        end

        def store_navigation_error(error, navigation_request:)
          return unless navigation_request

          @navigation_error = error if @navigation_error.nil?
        end
      end
    end
  end
end
