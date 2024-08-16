# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Channel do
  subject(:instance) { described_class.new(parsed_body, url:, response:) }

  let(:parsed_body) { Nokogiri::HTML('') }
  let(:url) { Addressable::URI.parse('https://example.com') }
  let(:response) do
    instance_double(Faraday::Response,
                    body: '',
                    headers: {
                      'content-type' => 'text/html',
                      'cache-control' => 'max-age=120, private, must-revalidate',
                      'last-modified' => 'Tue, 01 Jan 2019 00:00:00 GMT'
                    })
  end

  describe '#title' do
    context 'with a title' do
      let(:parsed_body) { Nokogiri::HTML('<html><head><title>Example</title></head></html>') }

      it 'extracts the title' do
        expect(instance.title).to eq('Example')
      end
    end

    context 'without a title' do
      let(:parsed_body) { Nokogiri::HTML('<html><head></head></html>') }

      it 'extracts nil' do
        expect(instance.title).to be_nil
      end
    end
  end

  describe '#language' do
    context 'with a language' do
      let(:parsed_body) { Nokogiri::HTML('<!doctype html><html lang="fr"><body></body></html>') }

      it 'extracts the language' do
        expect(instance.language).to eq('fr')
      end
    end

    context 'without a language' do
      let(:parsed_body) { Nokogiri::HTML('<html></html>') }

      it 'extracts nil' do
        expect(instance.language).to be_nil
      end
    end
  end

  describe '#description' do
    context 'with a description' do
      let(:parsed_body) do
        Nokogiri::HTML('<head><meta name="description" content="Example"></head>')
      end

      it 'extracts the description' do
        expect(instance.description).to eq('Example')
      end
    end

    context 'without a description' do
      let(:parsed_body) { Nokogiri::HTML('<head></head>') }

      it 'extracts an empty string' do
        expect(instance.description).to eq('')
      end
    end
  end

  describe '#image' do
    context 'with a og:image' do
      let(:parsed_body) do
        Nokogiri::HTML('<head><meta property="og:image" content="https://example.com/images/rock.jpg" />
</head>')
      end

      it 'extracts the url', :aggregate_failures do
        expect(instance.image).to be_a(Addressable::URI)
        expect(instance.image.to_s).to eq('https://example.com/images/rock.jpg')
      end
    end

    context 'without a og:image' do
      let(:parsed_body) { Nokogiri::HTML('<head></head>') }

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
      let(:response) do
        instance_double(Faraday::Response,
                        headers: {
                          'cache-control' => 'max-age=120, private, must-revalidate'
                        })
      end

      it 'extracts nil' do
        expect(instance.last_build_date).to be_nil
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