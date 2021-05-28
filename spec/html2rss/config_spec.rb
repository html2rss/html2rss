# frozen_string_literal: true

RSpec.describe Html2rss::Config do
  describe '.new' do
    context 'with missing required params' do
      it 'raises ParamsMissing' do
        expect do
          described_class.new(channel: { url: 'http://example.com/%<section>s' })
        end.to raise_error described_class::ParamsMissing
      end
    end
  end

  describe '.required_params_for_feed_config(feed_config)' do
    it do
      expect(
        described_class.required_params_for_feed_config(
          channel: { url: 'http://example.com/%<section>s/%<something>d' }
        )
      ).to be_a(Set).and include 'section', 'something'
    end
  end

  describe '#attribute_names' do
    subject { described_class.new(channel: {}, selectors: { items: {}, name: {} }).attribute_names }

    it { is_expected.to eq %i[name] }
  end

  describe '#category_selectors' do
    subject { described_class.new(feed_config).category_selectors }

    let(:feed_config) { { channel: {}, selectors: { categories: ['name', 'name', nil], name: {} } } }

    it { is_expected.to eq %i[name] }
  end

  describe '#title' do
    subject { described_class.new(feed_config).title }

    context 'with channel.title present' do
      let(:feed_config) { { channel: { title: 'An example channel' } } }

      it { is_expected.to eq feed_config[:channel][:title] }
    end

    context 'without channel.url having path' do
      let(:feed_config) { { channel: { url: 'http://www.example.com' } } }

      it { is_expected.to eq 'www.example.com' }
    end

    context 'with channel.url having path' do
      let(:feed_config) { { channel: { url: 'http://www.example.com/news' } } }

      it { is_expected.to eq 'www.example.com: News' }
    end
  end
end
