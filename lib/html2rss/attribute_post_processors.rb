module Html2rss
  ##
  # Provides a namespace for attribute post processors.
  module AttributePostProcessors
    def self.get_processor(name)
      camel_cased_name = name.split('_').map(&:capitalize).join
      class_name = ['Html2rss', 'AttributePostProcessors', camel_cased_name].join('::')
      Object.const_get(class_name)
    end
  end
end
