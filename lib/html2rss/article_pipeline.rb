# frozen_string_literal: true

module Html2rss
  ##
  # Processes article collections through a sequence of processors.
  #
  # @api private
  class ArticlePipeline
    ##
    # Default processors applied to every collection.
    #
    # @return [Array<#call>]
    def self.default_processors
      [Processors::Deduplicator.new]
    end

    ##
    # @param articles [Array<Html2rss::Article>] the collected articles
    # @param processors [Array<#call>] processors that transform the articles
    def initialize(articles, processors: self.class.default_processors)
      @articles = articles
      @processors = processors
    end

    ##
    # Executes the configured processors in order and returns the transformed collection.
    #
    # @return [Array<Html2rss::Article>]
    def call
      processors.reduce(articles) do |current_articles, processor|
        processor.call(current_articles)
      end
    end

    private

    attr_reader :articles, :processors
  end
end
