# frozen_string_literal: true

module Html2rss
  ##
  # Provides a namespace for attribute post processors.
  module AttributePostProcessors
    def self.get_processor(name)
      @get_processor ||= Hash.new do |processors, key|
        processors[key] = Utils.class_from_name(key, 'AttributePostProcessors')
      end

      @get_processor[name]
    end
  end
end
