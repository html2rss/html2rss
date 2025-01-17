# frozen_string_literal: true

require 'timecop'

RSpec.describe Html2rss::RssBuilder::Channel do
  subject(:instance) { described_class.new(response) }

  let(:response) do
    Html2rss::RequestService::Response.new body:,
                                           headers:,
                                           url: Addressable::URI.parse('https://example.com')
  end

  let(:body) { '' }
  let(:headers) do
    {
      'content-type' => 'text/html',
      'cache-control' => 'max-age=120, private, must-revalidate',
      'last-modified' => 'Tue, 01 Jan 2019 00:00:00 GMT'
    }
  end

  describe '#title' do
    context 'with a title' do
      let(:body) { '<html><head><title>Example</title></head></html>' }

      it 'extracts the title' do
        expect(instance.title).to eq('Example')
      end
    end

    context 'with a title containing extra spaces' do
      let(:body) { '<html><head><title>  Example   Title  </title></head></html>' }

      it 'extracts and strips the title' do
        expect(instance.title).to eq('Example Title')
      end
    end

    context 'without a title' do
      let(:body) { '<html><head></head></html>' }

      it 'generates a title from the URL' do
        allow(Html2rss::Utils).to receive(:titleized_channel_url).and_return('Example.com')
        expect(instance.title).to eq('Example.com')
      end
    end
  end

  describe '#language' do
    let(:headers) { { 'content-language' => nil, 'content-type': 'text/html' } }

    context 'with a language' do
      let(:body) { '<!doctype html><html lang="fr"><body></body></html>' }

      it 'extracts the language' do
        expect(instance.language).to eq('fr')
      end
    end

    context 'with a content-language header' do
      let(:headers) { { 'content-language' => 'en-US', 'content-type': 'text/html' } }

      it 'extracts the language' do
        expect(instance.language).to eq('en')
      end
    end

    context 'without a language' do
      let(:body) { '<html></html>' }

      it 'extracts nil' do
        expect(instance.language).to be_nil
      end
    end
  end

  describe '#description' do
    context 'with a description' do
      let(:body) do
        '<head><meta name="description" content="Example"></head>'
      end

      it 'extracts the description' do
        expect(instance.description).to eq('Example')
      end
    end

    context 'without a description' do
      let(:body) { '<head></head>' }

      it 'generates a default description' do
        expect(instance.description).to eq 'Latest items from https://example.com'
      end
    end
  end

  describe '#image' do
    context 'with a og:image' do
      let(:body) do
        '<head><meta property="og:image" content="https://example.com/images/rock.jpg" />
</head>'
      end

      it 'extracts the url', :aggregate_failures do
        expect(instance.image).to be_a(Addressable::URI)
        expect(instance.image.to_s).to eq('https://example.com/images/rock.jpg')
      end
    end

    context 'without a og:image' do
      let(:body) { '<head></head>' }

      it 'extracts nil' do
        expect(instance.image).to be_nil
      end
    end
  end

  describe '#last_build_date' do
    context 'with a last-modified header' do
      it 'extracts the last-modified header' do
        expect(instance.last_build_date).to eq('Tue, 01 Jan 2019 00:00:00 GMT')
      end
    end

    context 'without a last-modified header' do
      let(:headers) do
        {
          'content-type' => 'text/html',
          'cache-control' => 'max-age=120, private, must-revalidate'
        }
      end

      it 'defaults to Time.now' do
        Timecop.freeze(Time.now) do
          expect(instance.last_build_date).to eq Time.now
        end
      end
    end
  end

  describe '#ttl' do
    context 'with a cache-control header' do
      it 'extracts the ttl' do
        expect(instance.ttl).to eq(2)
      end
    end
  end
end
