# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Strategy do
  subject(:instance) { described_class.new(ctx) }

  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com') }

  describe '#execute' do
    it do
      expect { instance.execute }.to raise_error(NotImplementedError, /Subclass/)
    end
  end
end
