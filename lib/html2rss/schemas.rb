# frozen_string_literal: true

require 'dry/schema'

Dry::Schema.load_extensions(:hints)

module Html2rss
  ##
  # Provides a namespace for dry-schema
  module Schemas
    class ValidationError < StandardError; end

    FeedConfig = Dry::Schema.Params do
      required(:channel).hash(Channel)
      required(:selectors).hash(Selectors)
    end

    Channel = Dry::Schema.Params do
      required(:url).filled(:string)
      optional(:author).filled(:string)
      optional(:ttl).filled(:integer, gt?: 0)
      optional(:title).filled(:string)

      # TODO: validate: is one of the acceptable language codes
      optional(:language).filled(:string)
      optional(:description).filled(:string)

      # TODO: validate: is a known time zone
      optional(:time_zone).filled(:string)
      optional(:json).filled(:bool)

      optional(:headers).hash do
        # TODO: let it pass through String => String values
      end
    end

    Selectors = Dry::Schema.Params do
      required(:items).hash do
        required(:selector).filled(:string)
        # check if is 'reverse'
        optional(:order).filled(:string)
      end
      required(:url).hash(Selector)
    end

    Selector = Dry::Schema.Params do
      required(:selector).filled(:string)
    end

    def validate!(schema, data)
      result = schema.call(data)
      if result.failure?
        raise ValidationError, result.errors.to_h.each_pair.flat_map { |k, v|
                                 "#{k}: #{v.join(' and ')}"
                               }.join("\n")
      end

      result
    end
  end
end
