# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # The configured fields of one selector config, applied to an item node: single-field selects
    # (with the anchor +href+ as the +url+ default) and the article hash built from every selectable
    # field. Field compilation and execution live in {FieldPlan}.
    class ItemFields
      # Selector keys that may be copied onto an Article (PROVIDED_KEYS + mapped aliases).
      SELECTABLE_SELECTOR_KEYS = Set[*(Html2rss::Article::PROVIDED_KEYS + FieldPlan::SELECTOR_TO_ARTICLE_KEY.keys)].freeze

      # @param selectors [Hash] the feed config's +selectors+
      # @param items_key [Symbol] selector key of the items list, which is not a field
      def initialize(selectors, items_key:)
        @plan = FieldPlan.new(selectors, except: items_key)
        @article_fields = selectors.keys.select { SELECTABLE_SELECTOR_KEYS.include?(_1) }.map { @plan[_1] }
      end

      ##
      # @param name [Symbol] a configured selector key, or +:url+ on an anchor item
      # @param scope [ItemEnv]
      # @return [Object, Array<Object>, nil]
      # @raise [InvalidSelectorName] when +name+ is not defined for the item
      def select(name, scope)
        select_field(@plan[name], scope)
      end

      ##
      # @param scope [ItemEnv]
      # @return [Hash{Symbol => Object}] {Article} attributes, +url+ falling back to the anchor +href+
      def article_hash(scope)
        hash = @article_fields.each_with_object({}) do |field, h|
          value = select_field(field, scope)
          h[field.article_key] = article_value(field.article_key, value, scope) unless value.nil?
        end

        hash[:url] ||= default_url(scope) if anchor?(scope.item)
        hash
      end

      private

      def select_field(field, scope)
        return default_url(scope) if field.name == :url && field.config.nil? && anchor?(scope.item)

        @plan.select(field, scope)
      end

      def article_value(article_key, value, scope)
        case article_key
        when :enclosures then value.is_a?(Array) ? value : [value]
        when :url then resolve_url_value(value, scope.base_url)
        else value
        end
      end

      # A +url+ selector value that is a single whitespace-free string token (a +static+ value or a post-processor
      # result) resolves against the page URL like an +href+; a value that is no http(s) reference stays as given.
      # Text with surrounding words is left to +Article#url+'s sanitizer, which extracts the embedded URL.
      def resolve_url_value(value, base_url)
        return value unless value.is_a?(String) && value.match?(/\A\S+\z/)

        Url.resolve_web(value, base_url) || value
      end

      def anchor?(item) = item.name.to_s.casecmp('a').zero?

      def default_url(scope) = Url.resolve_web(scope.item['href'], scope.base_url, web_only: false)
    end
  end
end
