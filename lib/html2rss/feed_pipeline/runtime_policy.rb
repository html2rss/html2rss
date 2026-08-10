# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    ##
    # Planner for the runtime request policy and budgets of a feed run.
    #
    # HTTP request slots (pagination, document GETs, strategy fallback) are planned
    # separately from Browserless preload interaction budget so preload cannot steal
    # pagination slots.
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
            max_interactions: interaction_budget_for(config),
            total_timeout_seconds: policy.total_timeout_seconds
          )
        )
      end

      ##
      # Builds a Budget with separate request and interaction slot pools.
      #
      # @param config [Html2rss::Config] validated feed config
      # @return [Html2rss::RequestService::Budget] shared budget for the feed build
      def self.budget_for(config) = resources_for(config).budget

      ##
      # @param config [Html2rss::Config] validated feed config
      # @return [Integer] preload interaction slots derived from browserless preload config
      def self.interaction_budget_for(config)
        browserless_preload_budget_for(config)
      end

      class << self
        private

        def effective_max_requests_for(config)
          return config.max_requests if config.explicit_max_requests?

          [baseline_request_budget_for(config), config.max_requests].max
        end

        # Reserve enough HTTP request slots for the initial request plus predictable
        # follow-ups. Preload interactions are planned separately.
        def baseline_request_budget_for(config)
          1 +
            RequestSession::Pager.request_slots_for(config.selectors&.dig(:items, :pagination)) +
            AutoSource.request_slots_for(config.auto_source) +
            StrategyPlan.resolve(config.strategy).request_slots
        end

        def browserless_preload_budget_for(config)
          preload = config.request.dig(:browserless, :preload)
          return 0 unless preload

          top_level_preload_wait_budget(preload) +
            click_selector_preload_budget(preload) +
            scroll_preload_budget(preload)
        end

        def top_level_preload_wait_budget(preload)
          preload[:wait_after_ms] ? 2 : 0
        end

        def click_selector_preload_budget(preload)
          preload.fetch(:click_selectors, []).sum { preload_action_budget(_1, :max_clicks) }
        end

        def scroll_preload_budget(preload)
          scroll = preload[:scroll_down]
          return 0 unless scroll

          preload_action_budget(scroll, :iterations)
        end

        def preload_action_budget(config, count_key)
          action_count = config.fetch(count_key, 1)
          wait_budget = config[:wait_after_ms] ? action_count : 0

          action_count + wait_budget
        end
      end
    end
  end
end
