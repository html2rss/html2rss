module Html2rss
  ##
  # Provides a namespace for attribute post processors.
  module AttributePostProcessors
    def self.get_processor(name)
      @get_processor ||= Hash.new do |processors, key|
        camel_cased_name = key.split('_').map(&:capitalize).join
        class_name = ['Html2rss', 'AttributePostProcessors', camel_cased_name].join('::')
        processors[key] = Object.const_get(class_name)
      end

      @get_processor[name]
    end
  end
end
