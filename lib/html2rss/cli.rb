# frozen_string_literal: true

require 'thor'

##
# The Html2rss namespace / command line interface.
module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor
    check_unknown_options!

    def self.exit_on_failure?
      true
    end

    desc 'feed YAML_FILE [feed_name]', 'Print RSS built from the YAML_FILE file to stdout'
    method_option :params,
                  type: :hash,
                  optional: true,
                  required: false,
                  default: {}
    method_option :strategy,
                  type: :string,
                  desc: 'The strategy to request the URL',
                  enum: RequestService.strategy_names,
                  default: RequestService.default_strategy_name
    def feed(yaml_file, feed_name = nil)
      config = Html2rss.config_from_yaml_file(yaml_file, feed_name)
      config[:strategy] ||= options[:strategy]&.to_sym
      config[:params] = options[:params]

      puts Html2rss.feed(config)
    end

    desc 'auto [URL]', 'Automatically sources an RSS feed from the URL'
    method_option :strategy,
                  type: :string,
                  desc: 'The strategy to request the URL',
                  enum: RequestService.strategy_names,
                  default: RequestService.default_strategy_name
    method_option :items_selector, type: :string, desc: 'CSS selector for items (will be enhanced) (optional)'
    def auto(url)
      strategy = options.fetch(:strategy) { RequestService.default_strategy_name }.to_sym

      puts Html2rss.auto_source(url, strategy:, items_selector: options[:items_selector])
    end
  end
end
