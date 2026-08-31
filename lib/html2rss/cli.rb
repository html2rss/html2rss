# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'thor'

module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    check_unknown_options!

    # Supported CLI strategy names.
    STRATEGY_OPTION_ENUM = Html2rss::FeedPipeline::StrategyPlan.accepted_names.map(&:to_s).freeze
    # CLI strategy option description text.
    STRATEGY_OPTION_DESC =
      'Optional request strategy (defaults to auto; ' \
      "auto tries #{Html2rss::FeedPipeline::AutoFallback::CHAIN.join(' -> ')})".freeze

    ##
    # @return [Boolean] whether Thor should exit on command failure
    def self.exit_on_failure?
      true
    end

    desc 'recon [TARGET]', 'Probe a URL or candidate list for redirect chains, native feeds, and surface readiness'
    method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
    method_option :file, type: :string, desc: 'Candidate list file (one URL or slug\turl per line)'
    method_option :cache_dir, type: :string, desc: 'Directory to cache raw HTML snapshots'
    method_option :verdict, type: :string, desc: 'Filter batch output by verdict (BUILD, DEFER, DROP)'
    method_option :url_only, type: :boolean, desc: 'Emit only URLs matching verdict (for pipe chaining)', default: false
    method_option :format, type: :string, enum: %w[text json tsv], default: 'text'
    method_option :quiet, aliases: '-q', type: :boolean, default: false
    # @param target [String, nil] URL, file, or '-' for stdin
    # @return [void]
    def recon(target = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      urls, batch_mode = resolve_recon_targets(target, options[:file])
      raise Thor::Error, 'A target URL, --file, or stdin (-) is required' if urls.empty?

      results = Html2rss::Recon.batch(
        urls,
        strategy: current_strategy,
        cache_dir: options[:cache_dir]
      )

      filtered = filter_recon_results(results, options[:verdict])
      render_recon_output(filtered, batch_mode)

      return if batch_mode || filtered.empty?

      exit(3) if filtered.first.defer?
      exit(1) if filtered.first.drop?
    end

    desc 'capture [TARGET]', 'Analyze a URL or HTML and output a curated YAML feed config'
    method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
    method_option :items_selector, type: :string, desc: 'CSS selector hint for items'
    method_option :output_dir, aliases: '-o', type: :string, desc: 'Base directory to write domain/slug.yml'
    method_option :write, aliases: '-w', type: :string, desc: 'Specific file path to write YAML to'
    method_option :topics, aliases: '-t', type: :string, desc: 'Comma-separated directory topics'
    method_option :title, type: :string, desc: 'Directory and channel title override'
    method_option :summary, type: :string, desc: 'Directory summary override'
    method_option :enhance, type: :boolean, desc: 'Force enhance: true on items selector'
    method_option :force, type: :boolean, desc: 'Bypass native feed check', default: false
    method_option :input, type: :string, desc: 'Local HTML file path'
    method_option :limit, type: :numeric, desc: 'Article limit (default: 25)'
    method_option :explain, type: :boolean, desc: 'Print capture diagnostics to stderr', default: false
    # @param target [String, nil] URL or local HTML file
    # @return [void]
    def capture(target = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
      strategy, local_file_path, url = prepare_auto_inputs(target, options[:input])
      topics = options[:topics]&.split(',')&.map(&:strip)

      result = Html2rss::Capture.build(
        url,
        strategy:,
        items_selector: options[:items_selector],
        topics:,
        title: options[:title],
        summary: options[:summary],
        force: options[:force],
        enhance: options[:enhance],
        limit: options[:limit]&.to_i,
        local_file_path:
      )

      if result.native_feed? && !options[:force]
        $stderr.puts "First-party RSS/Atom feed detected at #{result.native_feed}. Use --force to capture anyway." # rubocop:disable Style/StderrPuts
        exit(3)
      end

      explain_capture!(result) if options[:explain]
      handle_capture_output(result, url)
    end

    desc 'test [CONFIG_INPUT] [feed_name]', 'Validate schema AND execute live extraction (fails on 0 items)'
    method_option :params, type: :hash, default: {}
    method_option :min_items, type: :numeric, default: 1, desc: 'Minimum required articles to pass'
    method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
    method_option :json, type: :boolean, desc: 'Output test outcome as JSON', default: false
    method_option :xml, type: :boolean, desc: 'Dump RSS XML alongside summary', default: false
    method_option :quiet, aliases: '-q', type: :boolean, default: false
    # @param config_input [String, nil] YAML file path, content, or '-' for stdin
    # @param feed_name [String, nil] optional feed name
    # @return [void]
    def test(config_input = nil, feed_name = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      raw_content, input_source = read_config_input(config_input)
      result = Html2rss.test(
        raw_content,
        feed_name,
        min_items: options[:min_items]&.to_i || 1,
        params: options[:params] || {},
        strategy: options[:strategy]
      )

      if options[:json]
        puts JSON.pretty_generate(result.to_h)
      elsif options[:quiet]
        $stderr.puts(result.error_message) unless result.success # rubocop:disable Style/StderrPuts
      elsif input_source == 'stdin' && !$stdout.tty? && !options[:xml]
        # Piped filter: echo config to stdout on success, write failure to stderr
        if result.success
          puts raw_content
        else
          $stderr.puts "Test failed: #{result.error_message}" # rubocop:disable Style/StderrPuts
        end
      else
        render_test_card(result, input_source)
        puts Html2rss.feed(raw_content) if options[:xml] && result.success
      end

      raise Thor::Error, (result.error_message || 'Test failed') unless result.success
    end

    desc 'feed SOURCE [feed_name]', 'Print RSS built from YAML config or direct URL to stdout'
    method_option :params, type: :hash, default: {}
    method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
    method_option :format, type: :string, enum: %w[rss jsonfeed], default: 'rss'
    method_option :max_redirects, type: :numeric, desc: 'Max redirects to follow'
    method_option :max_requests, type: :numeric, desc: 'Max request budget'
    method_option :limit, type: :numeric, desc: 'Max articles (auto-source)'
    method_option :items_selector, type: :string, desc: 'CSS selector for items (auto-source)'
    method_option :input, type: :string, desc: 'Local HTML file path'
    method_option :explain, type: :boolean, desc: 'Print status JSON to stderr', default: false
    # @param source [String, nil] YAML file path, URL, or '-'
    # @param feed_name [String, nil] optional named feed
    # @return [void]
    def feed(source = nil, feed_name = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
      if source.to_s.match?(%r{\Ahttps?://}i)
        auto(source)
      else
        config = if File.file?(source.to_s)
                   Html2rss.config_from_yaml_file(source.to_s, feed_name)
                 else
                   raw_content, = read_config_input(source)
                   Config.from_yaml(raw_content)
                 end
        config[:params] = options[:params] || {}
        apply_runtime_request_overrides!(config)
        apply_local_file_input!(config, options[:input]) if options[:input]

        feed_res = execute_feed { Html2rss.feed_result(config) }
        explain_status!(feed_res.status) if options[:explain]

        format = options.fetch(:format, 'rss')
        puts(format == 'jsonfeed' ? JSON.pretty_generate(feed_res.to_json_feed) : feed_res.to_rss)
      end
    end

    desc 'auto [URL]', 'Automatically source an RSS feed from a URL (alias to feed URL)'
    method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
    method_option :format, type: :string, enum: %w[rss jsonfeed], default: 'rss'
    method_option :items_selector, type: :string, desc: 'CSS selector hint for items'
    method_option :max_redirects, type: :numeric
    method_option :max_requests, type: :numeric
    method_option :limit, type: :numeric
    method_option :input, type: :string
    method_option :explain, type: :boolean, default: false
    # @param url [String, nil]
    # @return [void]
    def auto(url = nil)
      format = options.fetch(:format, 'rss')
      strategy, local_file_path, url = prepare_auto_inputs(url, options[:input])
      feed_result = execute_feed { auto_feed_result_for(url, strategy, local_file_path) }

      explain_status!(feed_result.status) if options[:explain]
      puts(format == 'jsonfeed' ? JSON.pretty_generate(feed_result.to_json_feed) : feed_result.to_rss)
    end

    desc 'validate [CONFIG_FILES...]', 'Validate one or more YAML configs against the JSON Schema'
    method_option :params, type: :hash, default: {}
    method_option :quiet, aliases: '-q', type: :boolean, default: false
    # @param files [Array<String>] file paths or globs
    # @return [void]
    def validate(*files) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      if files.size == 2 && File.file?(files[0].to_s) && !File.exist?(files[1].to_s)
        file = files[0]
        feed_name = files[1]
        result = Html2rss.validate(file, feed_name, params: options[:params] || {})
        raise Thor::Error, "Invalid configuration: #{result.errors.to_h}" unless result.success?

        puts 'Configuration is valid' unless options[:quiet]
        return

      end

      target_files = resolve_validate_files(files)
      failed = []

      target_files.each do |file|
        result = if file == '-'
                   Html2rss.validate($stdin.read, params: options[:params] || {})
                 else
                   Html2rss.validate(file, params: options[:params] || {})
                 end

        if result.success?
          puts(target_files.size == 1 ? 'Configuration is valid' : "ok   #{file}") unless options[:quiet]
        else
          error_details = result.errors.to_h
          raise Thor::Error, "Invalid configuration: #{error_details}" if target_files.size == 1

          warn "FAIL #{file}"
          error_details.each { |key, msg| warn "       #{key}: #{Array(msg).join(', ')}" }
          failed << file

        end
      end

      return if failed.empty?

      raise Thor::Error, "#{failed.size}/#{target_files.size} configurations failed validation."
    end

    desc 'schema', 'Print or export the configuration JSON Schema'
    method_option :pretty, type: :boolean, default: true, desc: 'Pretty-print JSON'
    method_option :write, aliases: '-w', type: :string, desc: 'Write schema to file path'
    # @return [void]
    def schema
      schema_json = Html2rss.schema_json(pretty: options.fetch(:pretty, true))
      if options[:write]
        FileUtils.mkdir_p(File.dirname(options[:write]))
        File.write(options[:write], "#{schema_json}\n")
        puts options[:write]
      else
        puts schema_json
      end
    end

    desc 'mcp', 'Start the MCP server for AI agent and IDE consumption'
    method_option :transport, type: :string, enum: %w[stdio http], default: 'stdio'
    method_option :port, type: :numeric, default: 8080
    # @return [void]
    def mcp
      Html2rss::MCP.start(transport: options[:transport].to_sym, port: options[:port])
    end

    private

    def resolve_recon_targets(target, file_opt) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      if file_opt
        [File.readlines(file_opt, chomp: true).reject { |l| l.strip.empty? || l.start_with?('#') }, true]
      elsif target == '-'
        [$stdin.readlines.map(&:chomp).reject { |l| l.strip.empty? || l.start_with?('#') }, true]
      elsif target
        [Array(target), false]
      else
        [[], false]
      end
    end

    def filter_recon_results(results, verdict_filter)
      return results unless verdict_filter

      filter = verdict_filter.to_s.downcase
      results.select { |r| r.verdict.to_s == filter }
    end

    def render_recon_output(results, batch_mode) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      if options[:url_only]
        results.each { |r| puts r.requested_url }
      elsif options[:format] == 'json'
        data = results.map(&:to_h)
        puts(batch_mode ? JSON.pretty_generate(data) : JSON.pretty_generate(data.first))
      elsif options[:format] == 'tsv'
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
        results.each { |r| render_recon_card(r) }
      end
    end

    def render_recon_card(result) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      color = case result.verdict
              when :build then "\e[32m"
              when :defer then "\e[33m"
              else "\e[31m"
              end
      puts "#{color}[#{result.verdict.to_s.upcase}]\e[0m #{result.requested_url}"
      if result.final_url != result.requested_url
        puts "        Final:    #{result.final_url} (HTTP #{result.status || 'ERR'})"
      end
      puts "        Surface:  #{result.surface_category} (#{result.articles_count} articles)"
      puts "        Feed:     #{result.native_feed}" if result.native_feed
      puts "        Notes:    #{result.notes.join(', ')}" if result.notes.any?
      puts ''
    end

    def handle_capture_output(result, url) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      if options[:out]
        dir = File.join(options[:out], URI.parse(url).host.to_s.delete_prefix('www.'))
        FileUtils.mkdir_p(dir)
        file_path = File.join(dir, 'index.yml')
        File.write(file_path, result.yaml)
        puts "Wrote captured config to #{file_path}"
      elsif options[:write]
        FileUtils.mkdir_p(File.dirname(options[:write]))
        File.write(options[:write], result.yaml)
        puts "Wrote captured config to #{options[:write]}"
      else
        puts result.yaml
      end
    end

    def read_config_input(input)
      if input.nil? || input == '-'
        [$stdin.read, 'stdin']
      elsif File.file?(input)
        [File.read(input), input]
      else
        [input, 'raw_string']
      end
    end

    def render_test_card(result, source) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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

    def resolve_validate_files(files)
      return ['-'] if files.empty? || files == ['-']

      resolved = []
      files.each do |f|
        matched = Dir.glob(f)
        resolved.concat(matched.empty? ? [f] : matched)
      end
      resolved.uniq
    end

    def apply_runtime_request_overrides!(config)
      clear_blank_request_overrides!(config)
      request_controls.apply_to(config)
    end

    def clear_blank_request_overrides!(config)
      config.delete(:strategy) if config[:strategy].nil?

      request_config = config[:request]
      return unless request_config.is_a?(Hash)

      %i[max_redirects max_requests].each do |key|
        request_config.delete(key) if request_config[key].nil?
      end
      config.delete(:request) if request_config.empty?
    end

    def apply_local_file_input!(config, input_path)
      file_path = check_file_exists!(input_path)
      config[:strategy] = :local_file
      config[:request] = (config[:request] || {}).merge(local_file_path: file_path)

      return unless config.dig(:channel, :url).to_s.empty?

      config[:channel] = (config[:channel] || {}).merge(
        url: detect_base_url!(file_path, 'Please specify a channel.url in the config.')
      )
    end

    def prepare_auto_inputs(url, input_option)
      if input_option.nil?
        raise Thor::Error, 'A URL is required unless --input is specified' unless url

        return [current_strategy, nil, url]
      end

      file_path = check_file_exists!(input_option)
      detected_url = url || detect_base_url!(
        file_path, 'Please specify a URL: html2rss <command> [URL] --input <file>'
      )

      [:local_file, file_path, detected_url]
    end

    def request_controls
      Html2rss::Config::RequestControls.from_cli_options(
        strategy: options[:strategy],
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests]
      )
    end

    def current_strategy
      options[:strategy]&.to_sym || :auto
    end

    def execute_feed # rubocop:disable Metrics/MethodLength
      yield
    rescue Html2rss::RequestService::RedirectLimitReached => error
      raise Thor::Error,
            "#{error.message}. already retried the last redirect hop once; " \
            'retry with higher --max-redirects or use the final URL directly.'
    rescue Html2rss::RequestService::RequestBudgetExceeded => error
      raise Thor::Error,
            "#{error.message}. retry with higher --max-requests or increase request.max_requests in config."
    rescue Html2rss::RequestService::BotasaurusConfigurationError,
           Html2rss::RequestService::BotasaurusConnectionFailed,
           Html2rss::RequestService::BotasaurusServiceError,
           Html2rss::RequestService::BlockedSurfaceDetected,
           Html2rss::NoFeedItemsExtracted => error
      raise Thor::Error, error.message
    end

    def auto_feed_result_for(url, strategy, local_file_path)
      Html2rss.auto_feed_result(
        url,
        strategy:,
        items_selector: options[:items_selector],
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests],
        local_file_path:,
        limit: options[:limit]&.to_i
      )
    end

    def explain_status!(status)
      $stderr.puts JSON.pretty_generate(status.to_h) # rubocop:disable Style/StderrPuts
    end

    def explain_capture!(result) # rubocop:disable Metrics/MethodLength
      $stderr.puts JSON.pretty_generate( # rubocop:disable Style/StderrPuts
        {
          articles_count: result.articles_count,
          channel_title: result.channel_title,
          has_selectors: result.has_selectors,
          segment_strategy: result.segment_strategy,
          selected_strategy: result.selected_strategy,
          inferred_topics: result.inferred_topics,
          admission_drops: result.admission_drops
        }.compact
      )
    end

    def check_file_exists!(path)
      File.expand_path(path).tap do |file_path|
        raise Thor::Error, "Input file does not exist: #{path}" unless File.exist?(file_path)
      end
    end

    def detect_base_url!(file_path, error_hint)
      Html2rss::Url.extract_from_html(File.read(file_path))&.to_s ||
        raise(Thor::Error, "Could not auto-detect a base URL from HTML metadata. #{error_hint}")
    end
  end
end
