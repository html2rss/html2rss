# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Error do
  it { expect(described_class).to be < StandardError }
end
