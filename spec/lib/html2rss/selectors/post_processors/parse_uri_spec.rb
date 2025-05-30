# frozen_string_literal: true

require 'addressable'

RSpec.describe Html2rss::Selectors::PostProcessors::ParseUri do
  subject do
    described_class.new(url, context).get
  end

  let(:context) do
    Html2rss::Selectors::Context.new(
      config: { channel: { url: 'http://example.com' } }
    )
  end

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with URI value' do
    let(:url) { URI('http://example.com') }

    it { is_expected.to eq 'http://example.com' }
  end

  context 'with Addressable::URI value' do
    let(:url) { Addressable::URI.parse('http://example.com') }

    it { is_expected.to eq 'http://example.com' }
  end

  context 'with String value' do
    context 'with an absolute url containing a trailing space' do
      let(:url) { 'http://example.com ' }

      it { is_expected.to eq 'http://example.com' }
    end

    context 'with relative url' do
      let(:url) { '/foo/bar' }

      it { is_expected.to eq 'http://example.com/foo/bar' }
    end
  end
end
