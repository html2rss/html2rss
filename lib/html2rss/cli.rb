# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'thor'

module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    check_unknown_options!

    map 'feed' => 'apply'
    map 'auto' => 'scrape'

    # Supported CLI strategy names.
    STRATEGY_OPTION_ENUM = Html2rss::FeedPipeline::StrategyPlan.accepted_names.map(&:to_s).freeze
    # CLI strategy option description text.
    STRATEGY_OPTION_DESC =
      'Optional request strategy (defaults to auto; ' \
      "auto tries #{Html2rss::FeedPipeline::AutoFallback::CHAIN.join(' -> ')})".freeze

    # CLI `--file` description for inspect/recon candidate lists.
    RECON_FILE_DESC = 'Candidate list file (one URL or slug\turl per line)'

    ##
    # @return [Boolean] whether Thor should exit on command failure
    def self.exit_on_failure?
      true
    end

    # Shared Thor options for inspect/recon URL targets.
    def self.probe_target_options
      method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
      method_option :file, type: :string, desc: RECON_FILE_DESC
    end

    # Shared Thor request/transport options for feed-producing commands.
    def self.feed_transport_options
      method_option :strategy, type: :string, desc: STRATEGY_OPTION_DESC, enum: STRATEGY_OPTION_ENUM
      method_option :max_redirects, type: :numeric, desc: 'Max redirects to follow'
      method_option :max_requests, type: :numeric, desc: 'Max request budget'
      method_option :input, type: :string, desc: 'Local HTML file path'
    end

    # Shared Thor output options for apply/scrape.
    def self.feed_emit_options
      method_option :format, type: :string, enum: %w[rss jsonfeed], default: 'rss'
      method_option :explain, type: :boolean, desc: 'Print status JSON to stderr', default: false
    end

    probe_target_options
    desc 'inspect [TARGET]', 'Fetch diagnostics for a URL (final URL, status, alternates, surface)'
    method_option :format, type: :string, enum: %w[text json], default: 'text'
    method_option :deep, type: :boolean, default: false,
                         desc: 'Single Botasaurus diagnostic hop when BOTASAURUS_SCRAPER_URL is set'
    # @param target [String, nil] URL, file, or '-' for stdin
    # @return [void]
    def inspect(target = nil)
      with_recon_targets(target) do |urls, batch_mode|
        results = if batch_mode
                    Html2rss.batch_inspect(urls, strategy: current_strategy).results
                  else
                    [Html2rss.inspect(urls.first, strategy: current_strategy, deep: options[:deep]).to_wire_h]
                  end
        Render.inspect_output(results, format: options[:format], batch_mode:)
      end
    end

    probe_target_options
    desc 'recon [TARGET]', 'Probe a URL or candidate list for redirect chains, native feeds, and surface readiness'
    method_option :cache_dir, type: :string, desc: 'Directory to cache raw HTML snapshots'
    method_option :verdict, type: :string, desc: 'Filter batch output by verdict (BUILD, DEFER, DROP)'
    method_option :url_only, type: :boolean, desc: 'Emit only URLs matching verdict (for pipe chaining)', default: false
    method_option :format, type: :string, enum: %w[text json tsv], default: 'text'
    # @param target [String, nil] URL, file, or '-' for stdin
    # @return [void]
    def recon(target = nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      with_recon_targets(target) do |urls, batch_mode|
        results = Html2rss::Recon.batch(
          urls,
          strategy: current_strategy,
          cache_dir: options[:cache_dir]
        )
        filtered = filter_recon_results(results, options[:verdict])
        assert_recon_verdict_match!(filtered, results, batch_mode:)

        Render.recon_output(
          filtered,
          format: options[:format],
          batch_mode:,
          url_only: options[:url_only]
        )

        return if batch_mode || filtered.empty?

        exit(3) if filtered.first.defer?
        exit(1) if filtered.first.drop?
      end
    end

    feed_transport_options
    desc 'capture [TARGET]', 'Analyze a URL or HTML and output a curated YAML feed config'
    method_option :items_selector, type: :string, desc: 'CSS selector hint for items'
    method_option :output_dir, aliases: '-o', type: :string,
                               desc: 'Base directory to write <domain>/index.yml'
    method_option :write, aliases: '-w', type: :string, desc: 'Specific file path to write YAML to'
    method_option :topics, aliases: '-t', type: :string, desc: 'Comma-separated directory topics'
    method_option :title, type: :string, desc: 'Directory and channel title override'
    method_option :summary, type: :string, desc: 'Directory summary override'
    method_option :enhance, type: :boolean, desc: 'Force enhance: true on items selector'
    method_option :force, type: :boolean, desc: 'Bypass native feed check', default: false
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
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests],
        local_file_path:
      )

      if result.native_feed? && !options[:force]
        $stderr.puts "First-party RSS/Atom feed detected at #{result.native_feed}. Use --force to capture anyway." # rubocop:disable Style/StderrPuts
        exit(3)
      end

      explain_json!(capture_explain_payload(result)) if options[:explain]
      handle_capture_output(result, url)
    end

    desc 'test [CONFIG_INPUT] [feed_name]', 'Validate schema AND execute live extraction (fails on 0 items)'
    method_option :params, type: :hash, default: {}
    method_option :min_items, type: :numeric, default: 1, desc: 'Minimum required articles to pass'
    method_option :strict_quality, type: :boolean, default: false,
                                   desc: 'Fail when ship-quality audit thresholds are exceeded'
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
        min_items: options.fetch(:min_items, 1).to_i,
        params: options[:params] || {},
        strategy: options[:strategy],
        strict_quality: options.fetch(:strict_quality, false)
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
        Render.test_card(result, input_source)
        puts result.rss if options[:xml] && result.success
      end

      raise Thor::Error, (result.error_message || 'Test failed') unless result.success
    end

    feed_transport_options
    feed_emit_options
    desc 'apply [CONFIG_INPUT] [feed_name]', 'Print RSS built from YAML config to stdout'
    method_option :params, type: :hash, default: {}
    # @param source [String, nil] YAML file path or '-'
    # @param feed_name [String, nil] optional named feed
    # @return [void]
    def apply(source = nil, feed_name = nil) # rubocop:disable Metrics/AbcSize
      config = if File.file?(source.to_s)
                 Html2rss.config_from_yaml_file(source.to_s, feed_name)
               else
                 raw_content, = read_config_input(source)
                 Config.from_yaml(raw_content)
               end
      config[:params] = options[:params] || {}
      apply_runtime_request_overrides!(config)
      apply_local_file_input!(config, options[:input]) if options[:input]

      run_feed_command { Html2rss.apply(config) }
    end

    feed_transport_options
    feed_emit_options
    desc 'scrape [URL]', 'Automatically source an RSS feed from a URL (one-shot auto-source)'
    method_option :items_selector, type: :string, desc: 'CSS selector hint for items'
    method_option :limit, type: :numeric, desc: 'Max articles (auto-source)'
    # @param url [String, nil]
    # @return [void]
    def scrape(url = nil)
      strategy, local_file_path, url = prepare_auto_inputs(url, options[:input])
      run_feed_command { scrape_feed_result_for(url, strategy, local_file_path) }
    end

    desc 'validate [CONFIG_FILES...]', 'Validate one or more YAML configs against the JSON Schema'
    method_option :params, type: :hash, default: {}
    method_option :quiet, aliases: '-q', type: :boolean, default: false
    # @param files [Array<String>] file paths or globs
    # @return [void]
    def validate(*files)
      Validate.run(files, params: options[:params] || {}, quiet: options[:quiet])
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

    desc 'doctor [TYPE]', 'Runtime preflight checks (botasaurus)'
    method_option :sample, type: :string, desc: 'Optional URL for a Botasaurus sample scrape'
    # @param type [String, nil] check type (default: botasaurus)
    # @return [void]
    def doctor(type = 'botasaurus')
      case type.to_s
      when 'botasaurus'
        result = Html2rss::Doctor::Botasaurus.call(sample_url: options[:sample])
        explain_json!(result.to_h)
        raise Thor::Error, result.message unless result.ok
      else
        raise Thor::Error, "Unknown doctor type: #{type}. Supported: botasaurus"
      end
    end

    private

    def with_recon_targets(target)
      urls, batch_mode = resolve_recon_targets(target, options[:file])
      raise Thor::Error, 'A target URL, --file, or stdin (-) is required' if urls.empty?

      yield urls, batch_mode
    end

    def resolve_recon_targets(target, file_opt)
      if file_opt
        [parse_recon_lines(File.readlines(file_opt, chomp: true)), true]
      elsif target == '-'
        [parse_recon_lines($stdin.readlines.map(&:chomp)), true]
      elsif target
        [Array(target), false]
      else
        [[], false]
      end
    end

    def parse_recon_lines(lines)
      lines.filter_map do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?('#')

        stripped.include?("\t") ? stripped.split("\t", 2).last.strip : stripped
      end
    end

    def filter_recon_results(results, verdict_filter)
      return results unless verdict_filter

      expected = Recon::Verdict.coerce(verdict_filter.downcase)
      results.select { |r| r.verdict == expected }
    rescue ArgumentError => error
      raise Thor::Error, error.message
    end

    def assert_recon_verdict_match!(filtered, results, batch_mode:)
      return if batch_mode || !options[:verdict] || !filtered.empty? || results.empty?

      raise Thor::Error, "No results matched verdict #{options[:verdict].upcase}"
    end

    def run_feed_command(&)
      feed_res = execute_feed(&)
      explain_json!(feed_res.status.to_h) if options[:explain]
      emit_feed_result(feed_res, options.fetch(:format, 'rss'))
    end

    def emit_feed_result(feed_res, format)
      payload = format == 'jsonfeed' ? JSON.pretty_generate(feed_res.to_json_feed) : feed_res.to_rss
      puts payload
    end

    def handle_capture_output(result, url) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      if options[:output_dir]
        dir = File.join(options[:output_dir], URI.parse(url).host.to_s.delete_prefix('www.'))
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

    def scrape_feed_result_for(url, strategy, local_file_path)
      Html2rss.scrape(
        url,
        strategy:,
        items_selector: options[:items_selector],
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests],
        local_file_path:,
        limit: options[:limit]&.to_i
      )
    end

    def explain_json!(payload)
      $stderr.puts JSON.pretty_generate(payload) # rubocop:disable Style/StderrPuts
    end

    def capture_explain_payload(result)
      {
        articles_count: result.articles_count,
        channel_title: result.channel_title,
        has_selectors: result.has_selectors,
        segment_strategy: result.segment_strategy,
        selected_strategy: result.selected_strategy,
        inferred_topics: result.inferred_topics,
        admission_drops: result.admission_drops
      }.compact
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
