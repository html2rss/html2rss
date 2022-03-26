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

    it { is_expected.to eq Set.new(%i[name]) }
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

  describe '#title' do
    context 'with channel.title present' do
      subject { described_class.new(feed_config).title }

      let(:feed_config) do
        { channel: { title: 'An example channel', url: 'http://example.com/title' }, selectors: { items: {} } }
      end

      it 'uses the given title' do
        expect(subject).to eq feed_config[:channel][:title]
      end
    end

    context 'with channel.url having path' do
      let(:feed_config) { { channel: { url: 'http://www.example.com/news' }, selectors: { items: {} } } }

      it 'uses the Util method' do
        allow(Html2rss::Utils).to receive(:titleized_url).and_call_original
        described_class.new(feed_config).title
        expect(Html2rss::Utils).to have_received(:titleized_url).with('http://www.example.com/news')
      end
    end
  end

  describe '.headers' do
    context 'without channel headers' do
      it { expect(described_class.new(config).headers).to be_a Hash }
    end
  end
end
