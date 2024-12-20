# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'

module Html2rss
  class RequestService
    ##
    # Strategy to use Faraday for the request.
    # @see https://rubygems.org/gems/faraday
    class FaradayStrategy < Strategy
      # return [Response]
      def execute
        request = Faraday.new(url: ctx.url, headers: ctx.headers) do |faraday|
          faraday.use Faraday::FollowRedirects::Middleware
          faraday.adapter Faraday.default_adapter
        end
        response = request.get

        Response.new(body: response.body, headers: response.headers)
      end
    end
  end
end
