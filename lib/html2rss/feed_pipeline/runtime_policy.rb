# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    ##
    # Planner for the runtime request policy and budgets of a feed run.
    #
    # HTTP request slots (pagination, document GETs, strategy fallback) are planned
    # from configuration options.
    class RuntimePolicy
      # Policy plus Budget from one config expansion (shared meters for a feed run).
      Resources = Data.define(:policy, :budget)

      ##
      # @param config [Html2rss::Config] validated feed config
      # @return [Html2rss::RequestService::Policy] request policy derived from runtime config
      def self.from_config(config)
        RequestService::Policy.new(
          max_requests: effective_max_requests_for(config),
          max_redirects: config.max_redirects,
          total_timeout_seconds: config.total_timeout_seconds || RequestService::Policy::DEFAULTS[:total_timeout_seconds]
        )
      end

      ##
      # Builds policy and budget from one `from_config` so FeedPipeline does not dual-own expansion.
      #
      # @param config [Html2rss::Config] validated feed config
      # @return [Resources] shared policy + budget for the feed build
      def self.resources_for(config)
        policy = from_config(config)
        Resources.new(
          policy:,
          budget: RequestService::Budget.new(
            max_requests: policy.max_requests,
            total_timeout_seconds: policy.total_timeout_seconds
          )
        )
      end

      ##
      # Builds a Budget with request slot pools.
      #
      # @param config [Html2rss::Config] validated feed config
      # @return [Html2rss::RequestService::Budget] shared budget for the feed build
      def self.budget_for(config) = resources_for(config).budget

      class << self
        private

        def effective_max_requests_for(config)
          return config.max_requests if config.explicit_max_requests?

          [baseline_request_budget_for(config), config.max_requests].max
        end

        # Reserve enough HTTP request slots for the initial request plus predictable
        # follow-ups.
        def baseline_request_budget_for(config)
          1 +
            RequestSession::Pager.request_slots_for(config.selectors&.dig(:items, :pagination)) +
            AutoSource.request_slots_for(config.auto_source) +
            FeedResolution.request_slots_for(config.auto_source) +
            StrategyPlan.resolve(config.strategy).request_slots
        end
      end
    end
  end
end
