# frozen_string_literal: true

module Html2rss
  class RequestService
    class PuppetCommander
      ##
      # Runs Browserless preload choreography: wait, click, and scroll against
      # the interaction budget on {Context#budget}.
      class PreloadRunner
        ##
        # @param ctx [Context] request context providing preload config and budget
        def initialize(ctx:)
          @ctx = ctx
        end

        ##
        # Executes configured preload actions on the page, if any.
        #
        # @param page [Puppeteer::Page] browser page after initial navigation
        # @return [void]
        def call(page)
          preload_config = ctx.browserless_preload
          return unless preload_config

          wait_after(page, preload_config[:wait_after_ms])
          click_selectors(page, preload_config[:click_selectors]) if preload_config[:click_selectors]
          scroll_down(page, preload_config[:scroll_down]) if preload_config[:scroll_down]
          wait_after(page, preload_config[:wait_after_ms])
        end

        private

        attr_reader :ctx

        def wait_after(page, timeout_ms)
          return unless timeout_ms

          ctx.budget.consume_interaction!
          page.wait_for_timeout(timeout_ms)
        end

        def click_selectors(page, selectors)
          selectors.each { |selector_config| click_selector(page, selector_config) }
        end

        def scroll_down(page, config)
          iterations = config.fetch(:iterations, 1)
          wait_after_ms = config[:wait_after_ms]
          previous_height = nil

          iterations.times do
            updated_height = perform_scroll_iteration(page, wait_after_ms, previous_height)
            break unless updated_height

            previous_height = updated_height
          end
        end

        def click_selector(page, config)
          selector = config.fetch(:selector)
          max_clicks = config.fetch(:max_clicks, 1)
          wait_after_ms = config[:wait_after_ms]

          max_clicks.times do
            break unless (element = page.query_selector(selector))

            ctx.budget.consume_interaction!
            element.click
            wait_after(page, wait_after_ms)
          end
        end

        def perform_scroll_iteration(page, wait_after_ms, previous_height)
          ctx.budget.consume_interaction!
          page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
          wait_after(page, wait_after_ms)

          current_height = page.evaluate('() => document.body.scrollHeight')
          return if previous_height && current_height <= previous_height

          current_height
        end
      end
    end
  end
end
