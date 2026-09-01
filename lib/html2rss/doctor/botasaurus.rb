# frozen_string_literal: true

require 'faraday'
require 'json'

module Html2rss
  ##
  # CLI runtime health checks for optional scrape dependencies.
  module Doctor
    ##
    # Preflight checks for Botasaurus scrape-api connectivity.
    module Botasaurus
      ##
      # One named doctor check outcome.
      Check = Data.define(:name, :ok, :detail) do
        ##
        # @return [Hash{Symbol => Object}]
        def to_h
          { name: name.to_s, ok:, detail: }
        end
      end

      ##
      # Aggregate doctor command outcome.
      Result = Data.define(:ok, :checks, :message) do
        ##
        # @return [Hash{Symbol => Object}]
        def to_h
          { ok:, message:, checks: checks.map(&:to_h) }
        end
      end

      module_function

      ENV_VAR = 'BOTASAURUS_SCRAPER_URL'
      private_constant :ENV_VAR

      ##
      # @param sample_url [String, nil] optional URL for a sample scrape smoke test
      # @return [Result]
      def call(sample_url: nil) # rubocop:disable Metrics/AbcSize
        env = env_check
        checks = [env_check_record(env)]
        return missing_env_failure(checks) unless checks.first.ok

        checks << health_check_record(env[:base_url])
        return failure(checks, 'Botasaurus health check failed.') unless checks.last.ok

        checks << sample_scrape_record(sample_url) if sample_url
        return failure(checks, 'Sample scrape failed.') if sample_url && !checks.last.ok

        Log.info('doctor botasaurus: preflight passed')
        Result.new(ok: true, checks:, message: 'Botasaurus preflight passed.')
      end

      ##
      # @return [Hash{Symbol => Object}]
      def env_check
        base = ENV.fetch(ENV_VAR, '').strip
        {
          configured: MCP::Runtime.botasaurus_configured?,
          var: ENV_VAR,
          base_url: base.empty? ? nil : base
        }
      end

      ##
      # @param base_url [String]
      # @return [Hash{Symbol => Object}]
      def health_check(base_url)
        uri = Url.for_channel(base_url)
        client = Faraday.new(url: uri.to_s.chomp('/'), request: { timeout: 5 })
        response = client.get('/health')
        body = JSON.parse(response.body)
        { ok: response.status == 200, status: response.status, version: body['version'] }
      rescue StandardError => error
        { ok: false, error: "#{error.class}: #{error.message}" }
      end

      ##
      # @param url [String]
      # @return [Hash{Symbol => Object}]
      def sample_scrape(url)
        wire = PageRecon::Diagnostics.call(url:, strategy: :botasaurus).to_wire_h
        {
          ok: wire[:status].to_i.between?(200, 399),
          status: wire[:status],
          articles_count: wire[:articles_count]
        }
      rescue StandardError => error
        { ok: false, error: "#{error.class}: #{error.message}" }
      end

      def env_check_record(env = env_check)
        Check.new(name: :env, ok: env[:configured], detail: { var: env[:var], base_url_set: !env[:base_url].nil? })
      end
      module_function :env_check_record
      private_class_method :env_check_record

      def health_check_record(base_url)
        return Check.new(name: :health, ok: false, detail: { error: 'missing base URL' }) unless base_url

        health = health_check(base_url)
        Check.new(name: :health, ok: health[:ok], detail: health)
      end
      module_function :health_check_record
      private_class_method :health_check_record

      def sample_scrape_record(url)
        sample = sample_scrape(url)
        Check.new(name: :sample_scrape, ok: sample[:ok], detail: sample)
      end
      module_function :sample_scrape_record
      private_class_method :sample_scrape_record

      def missing_env_failure(checks)
        Log.info("doctor botasaurus: #{ENV_VAR} unset")
        failure(checks, "Set #{ENV_VAR} to the scrape-api base URL.")
      end
      module_function :missing_env_failure
      private_class_method :missing_env_failure

      def failure(checks, message)
        Result.new(ok: false, checks:, message:)
      end
      module_function :failure
      private_class_method :failure
    end
  end
end
