# frozen_string_literal: true

module Html2rss
  module MCP
    class Outcome
      ##
      # Single source of truth for MCP agent instructions, next-step guidance,
      # and prompt bodies. {Server} delegates here — do not duplicate prose in
      # +server.rb+.
      class Playbook
        # Default guidance copy keyed by {Outcome::NextStep::NAMES}.
        GUIDANCE = {
          done: 'Done. Read payload for the result.',
          inspect: 'Call inspect next. Read payload for diagnostics (final_url, status, ' \
                   'scheme_downgrade, alternate_feeds, likely_js_shell, redirect_summary).',
          recon: 'Call recon next. Read payload for verdict and native_feed preference.',
          validate: 'Call validate with payload.yaml or a config hash (XOR, not both).',
          apply: 'Call apply next. Confirm payload.item_count before shipping.',
          scrape: 'Call scrape for articles now. strategy auto already runs Faraday then Botasaurus ' \
                  'and promotes native RSS/Atom when present.',
          capture: 'Call capture for a reusable YAML draft, then follow next_step.',
          read_runtime: 'Read html2rss://runtime. Compare mcp_contract_version and catalog_fingerprint ' \
                        'to your cached tools/list before retrying unknown tools. ' \
                        'Set BOTASAURUS_SCRAPER_URL on the MCP process if botasaurus_configured is false.',
          test: 'Call test next (schema + live extraction). Confirm payload.item_count, ' \
                'failure_kind, and payload.quality_report warnings before shipping.'
        }.freeze

        class << self
          ##
          # Published MCP server instructions (decision tree for agents).
          #
          # @return [String]
          def instructions # rubocop:disable Metrics/MethodLength -- agent decision tree is the published contract
            <<~TEXT.strip
              html2rss MCP — decide which tool to call:

              1. Need articles now (no saved config)? → scrape (or batch_scrape for multiple)
                 - strategy "auto" runs Faraday → Botasaurus AutoFallback. Do not retry with explicit faraday after auto.
                 - Empty scrape is still success (articles-now). Follow next_step / guidance (read_runtime if Botasaurus unset).
              2. Need a reusable feed YAML? → capture → test → apply
                 - capture returns YAML inside payload.yaml. Draft only: if destination is html2rss-configs, rewrite for directory.topics and explicit channel title/url. Default enhance follows capture evidence (false when admission_drops show chrome); override only when needed.
                 - test runs schema + live extraction (min items). apply is the ship gate (isError on zero items). Confirm payload.item_count and payload.quality_report warnings (including enhance_gains when selectors.items.enhance is true). Use compare_enhance on test for enhance on/off diagnostics.
                 - validate alone is for schema-only checks; on success next_step is test.
              3. Weak scrape/capture or recon (final URL, status, https→http, rel=alternate feeds)? → inspect (or batch_inspect). Read likely_js_shell vs blocked_surface when articles_count is 0. When alternates warrant it, inspect next_step is recon.
              4. Have a config already? → validate (must succeed) → test → apply
              5. Schema / extractors / strategies / runtime → resources html2rss://schema|extractors|strategies|runtime
                 - runtime publishes version, mcp_contract_version, catalog_fingerprint, tools, botasaurus_configured.
                 - Refresh tools/list when catalog_fingerprint differs from your cache.

              Prefer capture for durable config; scrape / batch_scrape for one-shot extraction.
              Follow envelope next_step and guidance. Botasaurus needs BOTASAURUS_SCRAPER_URL in this process env (read html2rss://runtime; the URL is never returned).

              Future (not implemented): selectors.items.enhance_detail would fetch each item URL and run ArticleExtractor on detail HTML; default remains list-card enhance only.
            TEXT
          end

          ##
          # @param url [String]
          # @return [String]
          def scrape_webpage_prompt(url)
            <<~MSG.strip
              Scrape #{url} with scrape (strategy auto). One call is enough — auto already runs Faraday then Botasaurus.
              Follow envelope next_step and guidance. Call inspect only if articles are empty/weak or you need diagnostics (final_url, status, scheme_downgrade, alternate_feeds). When inspect finds alternates, follow next_step to recon.
              Do not retry scrape with explicit faraday after auto. Read html2rss://runtime if next_step is read_runtime.
              Return payload.items (not a raw JSON array).
            MSG
          end

          ##
          # @param url [String]
          # @return [String]
          def capture_feed_config_prompt(url)
            <<~MSG.strip
              Build a reusable html2rss feed config for #{url}:
              1) capture — YAML is payload.yaml. Check payload.articles_count, payload.has_selectors, and payload.suggested_channel_url. enhance defaults from admission evidence (false when chrome drops are high). When payload.native_feed is set, follow next_step (done — use the native feed).
              2) Follow next_step. If weak or you need recon, inspect then recon when alternates warrant it. Auto already hops to Botasaurus; do not retry capture with botasaurus unless Faraday was blocked.
              3) test with yaml (or config hash) — schema + live extraction. On :schema failure, validate; on :execution/:min_items, recapture. Read payload.quality_report.enhance_gains when enhance is on; optional compare_enhance compares enhance off vs on without changing shipped RSS.
              4) apply — isError if zero items. Confirm payload.item_count and payload.quality_report (including enhance_gains) before shipping.
              If the destination is html2rss-configs, rewrite the draft for directory.topics and explicit channel title/url. Return YAML.
            MSG
          end

          ##
          # @param report [PageRecon::Diagnostics::Report]
          # @return [String]
          def inspect_guidance(report)
            return GUIDANCE.fetch(:inspect) unless report.articles_count.zero?

            empty_extract_guidance(report.data)
          end

          ##
          # @param data [Hash{Symbol => Object}]
          # @return [String]
          def empty_extract_guidance(data) # rubocop:disable Metrics/MethodLength
            if data[:blocked_surface] || data[:surface_category].to_s == 'blocked_surface'
              return 'Blocked or anti-bot interstitial likely. Retry scrape with strategy botasaurus once ' \
                     '(or CLI inspect --deep when BOTASAURUS_SCRAPER_URL is set). ' \
                     'Do not retry explicit faraday after auto.'
            end
            if data[:likely_js_shell]
              return 'JS-rendered shell likely (html_present, zero articles). Use strategy auto or botasaurus; ' \
                     'CLI inspect --deep for one Botasaurus diagnostic hop.'
            end

            'Empty extract on a static-looking page. Verify redirect_summary.final_url and surface; ' \
              'capture may need selector hints.'
          end

          ##
          # @param result [Html2rss::Recon::Result]
          # @param next_step [Outcome::NextStep]
          # @return [String]
          def recon_guidance(result, next_step)
            return next_step.guidance unless result.scheme_downgrade

            "#{next_step.guidance} HTTPS→HTTP downgrade detected: try one Botasaurus scrape before DROP."
          end
        end
      end
    end
  end
end
