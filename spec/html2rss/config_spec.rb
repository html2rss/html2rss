# frozen_string_literal: true

RSpec.describe Html2rss::Config do
  let(:config) do
    {
      channel: { url: 'http://example.com/config' },
      selectors: {
        items: { selector: 'li' }
      }
    }
  end

  describe '.new' do
    context 'with missing required params' do
      it 'raises ParamsMissing' do
        expect do
          described_class.new(channel: { url: 'http://example.com/%<section>s' }, selectors: { items: {} })
        end.to raise_error described_class::ParamsMissing, /section/
      end
    end
  end

  describe '#attribute_names' do
    subject { described_class.new(config.merge(selectors: { items: {}, name: {} })).attribute_names }

    it { is_expected.to eq %i[name] }
  end

  describe '#attribute_options(name)' do
    subject(:instance) { described_class.new(config) }

    let(:config) do
      {
        channel: { url: 'http://example.com' },
        selectors: {
          items: {},
          title: { selector: 'h1' }
        }
      }
    end

    it do
      expect(instance.selector_attributes_with_channel(:title)).to a_hash_including(selector: 'h1',
                                                                                    channel: Html2rss::Config::Channel)
    end
  end

  describe '#category_selectors' do
    subject { described_class.new(feed_config).category_selectors }

    let(:feed_config) do
      config.merge(selectors: { items: { selector: {} }, categories: ['name', 'name', nil], name: {} })
    end

    it { is_expected.to eq %i[name] }
  end

  describe '#title' do
    subject { described_class.new(feed_config).title }

    context 'with channel.title present' do
      let(:feed_config) do
        { channel: { title: 'An example channel', url: 'http://example.com/title' }, selectors: { items: {} } }
      end

      it { is_expected.to eq feed_config[:channel][:title] }
    end

    context 'without channel.url having path' do
      let(:feed_config) { { channel: { url: 'http://www.example.com' }, selectors: { items: {} } } }

      it { is_expected.to eq 'www.example.com' }
    end

    context 'with channel.url having path' do
      let(:feed_config) { { channel: { url: 'http://www.example.com/news' }, selectors: { items: {} } } }

      it { is_expected.to eq 'www.example.com: News' }
    end
  end

  describe '.headers' do
    context 'without channel headers' do
      it { expect(described_class.new(config).headers).to be_a Hash }
    end
  end
end
