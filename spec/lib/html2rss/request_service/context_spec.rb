# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Context do
  describe '#initialize' do
    subject(:instance) { described_class.new(url:, headers:) }

    let(:url) { 'http://www.example.com' }
    let(:headers) { {} }

    context 'with a valid URL (String)' do
      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end

      it 'creates a valid context', :aggregate_failures do
        expect(instance.url).to be_a(Html2rss::Url)
        expect(instance.url.to_s).to eq('http://www.example.com')
        expect(instance.headers).to eq({})
      end
    end

    context 'with a valid URL (Html2rss::Url)' do
      let(:url) { Html2rss::Url.from_relative('http://example.com', 'http://example.com') }

      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end

      it 'creates a valid context', :aggregate_failures do
        expect(instance.url).to be_a(Html2rss::Url)
        expect(instance.url.to_s).to eq('http://example.com')
      end
    end

    context 'with custom headers' do
      let(:headers) { { 'User-Agent' => 'Custom Agent' } }

      it 'stores the headers' do
        expect(instance.headers).to eq(headers)
      end
    end
  end
end
