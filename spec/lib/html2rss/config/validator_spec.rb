# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::Validator do
  subject(:result) { described_class.new.call(config) }

  let(:base) do
    {
      channel: { url: 'https://example.com' },
      selectors: { items: { selector: '.article' } }
    }
  end

  describe 'selectors path bubbling' do
    let(:config) do
      base.merge(
        selectors: {
          items: { selector: '.article', pagination: { strategy: 'invalid_strategy' } }
        }
      )
    end

    it 'prefixes nested selector paths under :selectors', :aggregate_failures do
      expect(result).to be_failure
      expect(result.errors.map(&:path)).to include(%i[selectors items pagination])
    end
  end

  describe 'selector extractor path bubbling' do
    let(:config) do
      base.merge(
        selectors: {
          items: { selector: '.article' },
          title: { selector: 'h1', extractor: 'nope' }
        }
      )
    end

    it 'keeps the dynamic selector key and leaf', :aggregate_failures do
      expect(result).to be_failure
      expect(result.errors.map(&:path)).to include(%i[selectors title extractor])
    end
  end
end
