# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class Item
    # A context instance is passed to Item Extractors.
    Context = Struct.new('Context', :options, :item, :config, :scraper, keyword_init: true)
  end
end
