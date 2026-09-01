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
                   'scheme_downgrade, alternate_feeds).',
          recon: 'Call recon next. Read payload for verdict and native_feed preference.',
          validate: 'Call validate with payload.yaml or a config hash (XOR, not both).',
          apply: 'Call apply next. Confirm payload.item_count before shipping.',
          scrape: 'Call scrape for articles now. strategy auto already runs Faraday then Botasaurus ' \
                  'and promotes native RSS/Atom when present.',
          capture: 'Call capture for a reusable YAML draft, then follow next_step.',
          read_runtime: 'Read html2rss://runtime. Set BOTASAURUS_SCRAPER_URL on the MCP process ' \
                        'if botasaurus_configured is false.',
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
                 - capture returns YAML inside payload.yaml. Draft only: if destination is html2rss-configs, rewrite for directory.topics and explicit channel title/url. Strive enhance: true (false only when chrome leaks).
                 - test runs schema + live extraction (min items). apply is the ship gate (isError on zero items). Confirm payload.item_count and payload.quality_report warnings.
                 - validate alone is for schema-only checks; on success next_step is test.
              3. Weak scrape/capture or recon (final URL, status, https→http, rel=alternate feeds)? → inspect (or batch_inspect). When alternates warrant it, inspect next_step is recon.
              4. Have a config already? → validate (must succeed) → test → apply
              5. Schema / extractors / strategies / runtime → resources html2rss://schema|extractors|strategies|runtime

              Prefer capture for durable config; scrape / batch_scrape for one-shot extraction.
              Follow envelope next_step and guidance. Botasaurus needs BOTASAURUS_SCRAPER_URL in this process env (boolean at html2rss://runtime; the URL is never returned).
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
              1) capture — YAML is payload.yaml. Check payload.articles_count and payload.has_selectors. Strive to keep enhance: true (false only when chrome leaks into items). When payload.native_feed is set, follow next_step (done — use the native feed).
              2) Follow next_step. If weak or you need recon, inspect then recon when alternates warrant it. Auto already hops to Botasaurus; do not retry capture with botasaurus unless Faraday was blocked.
              3) test with yaml (or config hash) — schema + live extraction. On :schema failure, validate; on :execution/:min_items, recapture.
              4) apply — isError if zero items. Confirm payload.item_count before shipping.
              If the destination is html2rss-configs, rewrite the draft for directory.topics and explicit channel title/url. Return YAML.
            MSG
          end
        end
      end
    end
  end
end
