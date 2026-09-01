# frozen_string_literal: true

require 'json'

module Html2rss
  class CLI
    ##
    # Text and JSON rendering for CLI command output (display only; no policy).
    module Render
      # ANSI colors for recon verdict labels in text output.
      VERDICT_COLORS = { build: "\e[32m", defer: "\e[33m" }.freeze

      module_function

      ##
      # @param results [Array<Hash>]
      # @param format [String]
      # @param batch_mode [Boolean]
      # @return [void]
      def inspect_output(results, format:, batch_mode:)
        if format == 'json'
          json(results, batch_mode)
        else
          results.each { |data| probe_card(ProbeView.from_wire(data)) }
        end
      end

      ##
      # @param results [Array<Html2rss::Recon::Result>]
      # @param format [String]
      # @param batch_mode [Boolean]
      # @param url_only [Boolean]
      # @return [void]
      def recon_output(results, format:, batch_mode:, url_only: false) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if url_only
          results.each { |r| puts r.requested_url }
        elsif format == 'json'
          json(results.map(&:to_h), batch_mode)
        elsif format == 'tsv'
          puts %w[verdict status requested_url final_url native_feed notes].join("\t")
          results.each do |r|
            row = [
              r.verdict.to_s.upcase,
              r.status || '-',
              r.requested_url,
              r.final_url,
              r.native_feed || '-',
              r.notes.join('; ')
            ]
            puts row.join("\t")
          end
        else
          results.each { |r| probe_card(ProbeView.from_recon(r)) }
        end
      end

      ##
      # @param view [ProbeView]
      # @return [void]
      def probe_card(view) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if view.verdict
          color = VERDICT_COLORS.fetch(view.verdict.to_sym, "\e[31m")
          puts "#{color}[#{view.verdict.to_s.upcase}]\e[0m #{view.requested}"
        else
          puts view.requested
        end
        probe_lines(view)
        if view.alternate_feeds.any?
          hrefs = view.alternate_feeds.filter_map { |f| ProbeView.wire_val(f, :href) }
          puts "        Feeds:    #{hrefs.join(', ')}" if hrefs.any?
        end
        puts "        Feed:     #{view.native_feed}" if view.native_feed
        puts "        Notes:    #{view.notes.join(', ')}" if view.notes.any?
        puts "        Strategy: #{view.strategy}" if view.strategy
        puts ''
      end

      ##
      # @param result [Html2rss::Test::Result]
      # @param source [String]
      # @return [void]
      def test_card(result, source) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if result.success
          puts "\e[32m✓ Schema valid\e[0m (#{source})"
          dur = "#{result.duration_seconds}s"
          puts "\e[32m✓ Extracted #{result.item_count} items in #{dur}\e[0m (strategy: #{result.strategy_used})"
          puts "\nChannel: #{result.channel_title} (#{result.channel_url})"
          if result.sample_items.any?
            puts 'Sample items:'
            result.sample_items.each_with_index do |item, i|
              puts "  #{i + 1}. #{"#{item[:published_at]} | " if item[:published_at]}#{item[:title]}"
              puts "     #{item[:url]}"
            end
          end
        else
          warn "\e[31m✗ Test failed\e[0m (#{source})"
          warn "  Error: #{result.error_message}" if result.error_message
          result.validation_errors&.each { |k, v| warn "  Schema error [#{k}]: #{Array(v).join(', ')}" }
        end
      end

      ##
      # @param data [Object]
      # @param batch_mode [Boolean]
      # @return [void]
      def json(data, batch_mode)
        payload = batch_mode ? data : data.first
        puts JSON.pretty_generate(payload)
      end

      ##
      # @param view [ProbeView]
      # @return [void]
      def probe_lines(view)
        if view.final && view.final != view.requested
          puts "        Final:    #{view.final} (HTTP #{view.status || 'ERR'})"
        end
        surface = view.surface.respond_to?(:to_s) ? view.surface.to_s : view.surface
        puts "        Surface:  #{surface} (#{view.articles_count} articles)"
      end
      private_class_method :probe_lines
    end
  end
end
