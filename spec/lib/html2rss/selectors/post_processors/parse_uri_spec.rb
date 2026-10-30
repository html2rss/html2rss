# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::ParseUri do
  subject do
    described_class.new(url, context).call
  end

  let(:context) do
    Html2rss::Selectors::StepEnv.new(
      base_url: 'http://example.com'
    )
  end

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with Html2rss::Url value' do
    let(:url) { Html2rss::Url.from_absolute('http://example.com') }

    it { is_expected.to eq 'http://example.com/' }
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

  context 'with a missing or empty value' do
    it 'raises for an empty string' do
      expect { described_class.new('', context) }
        .to raise_error(ArgumentError, 'The `value` option is missing or empty.')
    end

    it 'raises for nil' do
      expect { described_class.new(nil, context) }
        .to raise_error(ArgumentError, 'The `value` option is missing or empty.')
    end
  end
end
