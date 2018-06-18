require_relative 'attribute_post_processors/parse_time'
require_relative 'attribute_post_processors/parse_uri'
require_relative 'attribute_post_processors/sanitize_html'
require_relative 'attribute_post_processors/substring'
require_relative 'attribute_post_processors/template'

module Html2rss
  module AttributePostProcessors
    def self.get_processor(options)
      camel_cased_option = options['name'].split('_').collect(&:capitalize).join
      class_name = ['Html2rss', 'AttributePostProcessors', camel_cased_option].join('::')

      Object.const_get(class_name)
    end
  end
end
