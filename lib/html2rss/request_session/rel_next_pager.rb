# frozen_string_literal: true

require_relative 'pager'

module Html2rss
  class RequestSession
    ##
    # Traverses a rel=next pagination chain for selector-driven extraction.
    class RelNextPager < Pager::RelNext
      ##
      # @param session [RequestSession] request session used to execute follow-ups
      # @param initial_response [RequestService::Response] first page response
      # @param max_pages [Integer] configured page budget, including the initial page
      # @param logger [Logger] logger used for pagination stop warnings
      def initialize(session:, initial_response:, max_pages:, logger: Html2rss::Log)
        super(session:, initial_response:, config: { max_pages: }, logger:)
      end
    end
  end
end
