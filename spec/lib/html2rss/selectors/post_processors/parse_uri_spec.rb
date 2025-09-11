# frozen_string_literal: true

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

  context 'with Html2rss::Url value' do
    let(:url) { Html2rss::Url.from_relative('http://example.com', 'http://example.com') }

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
