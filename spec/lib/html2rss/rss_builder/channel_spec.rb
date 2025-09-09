# frozen_string_literal: true

require 'addressable'
require 'timecop'

RSpec.describe Html2rss::RssBuilder::Channel do
  subject(:instance) { described_class.new(response, overrides:) }

  let(:overrides) { {} }
  let(:response) { build_response(body:, headers:, url:) }
  let(:body) { '' }
  let(:headers) { default_headers }
  let(:url) { Addressable::URI.parse('https://example.com') }

  # Test factories and shared data
  def build_response(body:, headers:, url:)
    Html2rss::RequestService::Response.new(body:, headers:, url:)
  end

  def default_headers
    {
      'content-type' => 'text/html',
      'cache-control' => 'max-age=120, private, must-revalidate',
      'last-modified' => 'Tue, 01 Jan 2019 00:00:00 GMT'
    }
  end

  def build_html_with_meta(name:, content:)
    "<head><meta name=\"#{name}\" content=\"#{content}\"></head>"
  end

  def build_html_with_property(property:, content:)
    "<head><meta property=\"#{property}\" content=\"#{content}\"></head>"
  end

  # Shared examples for override behavior
  shared_examples 'returns overridden value' do |method, override_key, expected_value|
    context "when overrides[:#{override_key}] is present" do
      let(:overrides) { { override_key => expected_value } }

      it { expect(instance.public_send(method)).to eq(expected_value) }
    end
  end

  shared_examples 'falls back to meta content' do |method, meta_name, expected_content|
    context "with #{meta_name} meta tag" do
      let(:body) { build_html_with_meta(name: meta_name, content: expected_content) }

      it { expect(instance.public_send(method)).to eq(expected_content) }
    end
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

    include_examples 'returns overridden value', :title, :title, 'Custom Title'

    context 'with empty title tag' do
      let(:body) { '<html><head><title></title></head></html>' }

      it 'generates a title from the URL' do
        allow(Html2rss::Utils).to receive(:titleized_channel_url).and_return('Example.com')
        expect(instance.title).to eq('Example.com')
      end
    end
  end

  describe '#language' do
    let(:headers) { { 'content-language' => nil, 'content-type': 'text/html' } }

    context 'with <html lang> attribute' do
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

    include_examples 'returns overridden value', :language, :language, 'es'

    context 'with lang attribute on a child element' do
      let(:body) { '<html><body><div lang="de">Content</div></body></html>' }

      it 'extracts the language from child element' do
        expect(instance.language).to eq('de')
      end
    end
  end

  describe '#description' do
    context 'with html_response having a description' do
      let(:body) do
        '<head><meta name="description" content="Example"></head>'
      end

      it 'extracts the description' do
        expect(instance.description).to eq('Example')
      end
    end

    context 'with html_response without having a description' do
      let(:body) { '<head></head>' }

      it 'generates a default description' do
        expect(instance.description).to eq 'Latest items from https://example.com'
      end
    end

    context 'when overrides[:description] is present and not empty' do
      let(:overrides) { { description: 'Overridden Description' } }

      it 'returns the overridden description' do
        expect(instance.description).to eq('Overridden Description')
      end
    end

    include_examples 'falls back to meta content', :description, 'description', 'Example'

    context 'when overrides[:description] is empty' do
      let(:overrides) { { description: '' } }
      let(:body) { build_html_with_meta(name: 'description', content: 'Example') }

      it 'falls back to meta description' do
        expect(instance.description).to eq('Example')
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

    include_examples 'returns overridden value', :image, :image, 'https://example.com/override.jpg'

    context 'with og:image meta tag' do
      let(:body) { build_html_with_property(property: 'og:image', content: 'https://example.com/image.jpg') }

      it 'extracts the image URL', :aggregate_failures do
        expect(instance.image).to be_a(Addressable::URI)
        expect(instance.image.to_s).to eq('https://example.com/image.jpg')
      end
    end

    context 'without html_response' do
      let(:body) { '' }
      let(:headers) { { 'content-type' => 'application/json' } }

      it 'returns nil' do
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

    context 'without a cache-control header' do
      let(:headers) { { 'content-type' => 'text/html' } }

      it 'defaults to 360 minutes' do
        expect(instance.ttl).to eq(360)
      end
    end

    include_examples 'returns overridden value', :ttl, :ttl, 60
  end

  describe '#author' do
    include_examples 'falls back to meta content', :author, 'author', 'John Doe'
    include_examples 'returns overridden value', :author, :author, 'Jane Doe'

    context 'without html_response' do
      let(:body) { '' }
      let(:headers) { { 'content-type' => 'application/json' } }

      it 'returns nil' do
        expect(instance.author).to be_nil
      end
    end
  end
end
