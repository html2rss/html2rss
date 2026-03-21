# frozen_string_literal: true

module Html2rss
  class RequestSession
    ##
    # Builds the runtime request policy for a feed run.
    class RuntimePolicy
      ##
      # @param config [Html2rss::Config] validated feed config
      # @return [Html2rss::RequestService::Policy] request policy derived from runtime config
      def self.from_config(config)
        RequestService::Policy.new(
          max_requests: effective_max_requests_for(config),
          max_redirects: config.max_redirects
        )
      end

      class << self
        private

        def effective_max_requests_for(config)
          return config.max_requests if config.explicit_max_requests?

          [baseline_request_budget_for(config), config.max_requests].max
        end

        # Reserve enough budget for the initial request plus predictable follow-ups
        # that the top-level pipeline may trigger during a normal feed build.
        def baseline_request_budget_for(config)
          1 + pagination_follow_up_budget_for(config) +
            known_auto_source_follow_up_budget_for(config) +
            browserless_preload_budget_for(config)
        end

        def pagination_follow_up_budget_for(config)
          [config.selectors&.dig(:items, :pagination, :max_pages).to_i - 1, 0].max
        end

        def known_auto_source_follow_up_budget_for(config)
          config.auto_source&.dig(:scraper, :wordpress_api, :enabled) ? 1 : 0
        end

        def browserless_preload_budget_for(config)
          preload = config.request.dig(:browserless, :preload)
          return 0 unless preload

          top_level_waits = preload[:wait_after_ms] ? 2 : 0
          click_actions = preload.fetch(:click_selectors, []).sum do |entry|
            entry.fetch(:max_clicks, 1) + (entry[:wait_after_ms] ? entry.fetch(:max_clicks, 1) : 0)
          end

          scroll_actions = if (scroll = preload[:scroll_down])
                             scroll.fetch(:iterations, 1) + (scroll[:wait_after_ms] ? scroll.fetch(:iterations, 1) : 0)
                           else
                             0
                           end

          top_level_waits + click_actions + scroll_actions
        end
      end
    end
  end
end
