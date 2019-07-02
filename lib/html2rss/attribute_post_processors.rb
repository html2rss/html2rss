require_relative 'attribute_post_processors/parse_time'
require_relative 'attribute_post_processors/parse_uri'
require_relative 'attribute_post_processors/sanitize_html'
require_relative 'attribute_post_processors/substring'
require_relative 'attribute_post_processors/template'

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
