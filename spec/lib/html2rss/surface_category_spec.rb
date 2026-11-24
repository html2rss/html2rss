# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/ExampleLength

RSpec.describe Html2rss::SurfaceCategory do
  it 'rejects unknown names' do
    expect { described_class[:maybe] }.to raise_error(Html2rss::InvalidOption, 'unknown surface category: :maybe')
  end

  it 'looks up symbols and strings', :aggregate_failures do
    expect(described_class[:app_shell]).to be_weak
    expect(described_class['listing']).to be_listing_bonus
  end

  it 'marks hub/shell surfaces as weak', :aggregate_failures do
    expect(described_class[:app_shell]).to be_weak
    expect(described_class[:high_entropy_surface]).to be_weak
    expect(described_class[:unsupported_surface]).to be_weak
  end

  it 'marks blocked separately from weak', :aggregate_failures do
    blocked = described_class[:blocked_surface]
    expect(blocked).to be_blocked
    expect(blocked).not_to be_weak
    expect(blocked).not_to be_listing_bonus
  end

  it 'grants listing bonus to the listing surface' do
    expect(described_class[:listing]).to be_listing_bonus
  end

  it 'does not treat listing as blocked' do
    expect(described_class[:listing]).not_to be_blocked
  end

  it 'exposes the surface name as a string and a symbol', :aggregate_failures do
    listing = described_class[:listing]

    expect(listing.to_s).to eq('listing')
    expect(listing.to_sym).to eq(:listing)
  end

  describe '.classify' do
    let(:classify) { ->(html) { described_class.classify(Nokogiri::HTML(html)) } }
    let(:interstitial_html) do
      '<html><head><title>Just a moment...</title></head>' \
        '<body>Checking your browser before accessing example.com.</body></html>'
    end
    let(:benign_html) { '<html><body><p>Plain page</p></body></html>' }

    it 'prefers the raw body over the parsed document for blocked detection', :aggregate_failures do
      expect(described_class.classify(Nokogiri::HTML(benign_html), body: interstitial_html))
        .to eq(:blocked_surface)
      expect(described_class.classify(Nokogiri::HTML(interstitial_html), body: benign_html))
        .to eq(:unsupported_surface)
    end

    it 'falls back to the parsed document when no body is given' do
      expect(classify.call(interstitial_html)).to eq(:blocked_surface)
    end

    it 'classifies blocked surfaces before high-entropy surfaces' do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS) { |index| %(<a href="/x/#{index}">X #{index}</a>) }
      html = interstitial_html.sub('<body>', "<body>#{links.join}")

      expect(classify.call(html)).to eq(:blocked_surface)
    end

    it 'classifies app shells, and high-entropy hubs ahead of app shells', :aggregate_failures do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS) { |index| %(<a href="/x/#{index}">X #{index}</a>) }

      expect(classify.call('<html><body><div id="root"></div></body></html>')).to eq(:app_shell)
      expect(classify.call("<html><body>#{links.join}</body></html>")).to eq(:high_entropy_surface)
      expect(classify.call(%(<html><body><div id="root"></div>#{links.join}</body></html>)))
        .to eq(:high_entropy_surface)
    end

    it 'classifies an empty page as unsupported' do
      expect(classify.call('<html><body></body></html>')).to eq(:unsupported_surface)
    end
  end

  describe '.classify app-shell' do
    let(:classify) { ->(html) { described_class.classify(Nokogiri::HTML(html)) } }

    it 'detects app shells for every root marker', :aggregate_failures do
      markers = [
        '<div id="app"></div>', '<div id="root"></div>', '<div id="__next"></div>',
        '<div data-reactroot></div>', '<div ng-app></div>', '<div id="site-app-shell"></div>'
      ]

      expect(markers.map { |marker| classify.call("<html><body>#{marker}</body></html>") })
        .to all(eq(:app_shell))
    end

    it 'does not treat a page without a root marker as an app shell' do
      expect(classify.call('<html><body><div id="main"></div></body></html>')).to eq(:unsupported_surface)
    end

    it 'tolerates up to APP_SHELL_MAX_ANCHORS anchors but not one more', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_ANCHORS
      within = Array.new(limit) { |index| %(<a href="/n/#{index}">N #{index}</a>) }.join
      over = Array.new(limit + 1) { |index| %(<a href="/n/#{index}">N #{index}</a>) }.join

      expect(classify.call(%(<html><body><div id="root"></div>#{within}</body></html>))).to eq(:app_shell)
      expect(classify.call(%(<html><body><div id="root"></div>#{over}</body></html>))).to eq(:unsupported_surface)
    end

    it 'rejects pages that carry article markers', :aggregate_failures do
      markers = [
        '<article>Story</article>',
        '<div itemtype="https://schema.org/NewsArticle">Story</div>',
        '<div itemprop="articleBody">Story</div>'
      ]

      expect(markers.map { |marker| classify.call(%(<html><body><div id="root"></div>#{marker}</body></html>)) })
        .to all(eq(:unsupported_surface))
    end

    it 'accepts visible text up to APP_SHELL_MAX_VISIBLE_TEXT_LENGTH but not one more', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH

      expect(classify.call(%(<html><body><div id="root"><p>#{'a' * limit}</p></div></body></html>)))
        .to eq(:app_shell)
      expect(classify.call(%(<html><body><div id="root"><p>#{'a' * (limit + 1)}</p></div></body></html>)))
        .to eq(:unsupported_surface)
    end
  end

  describe '.classify visible text' do
    let(:classify) { ->(html) { described_class.classify(Nokogiri::HTML(html)) } }

    it 'ignores script, style and noscript content', :aggregate_failures do
      html = '<html><body><div id="root"></div>' \
             "<noscript>#{'n' * 1_000}</noscript><style>#{'s' * 1_000}</style></body></html>"

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'collapses every whitespace run, not only the first' do
      words = Array.new(70) { 'ab' }.join('  ')
      html = %(<html><body><div id="root"></div><p>#{words}</p></body></html>)

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'collapses whitespace-only text to zero length' do
      html = %(<html><body><div id="root"></div><p>#{' ' * 1_000}</p></body></html>)

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'trims and collapses whitespace before measuring', :aggregate_failures do
      limit = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH
      padded = %(<html><body><div id="root"><p>   #{'a' * limit}   </p></div></body></html>)
      spaced = %(<html><body><div id="root"><p>a#{' ' * 1_000}b</p></div></body></html>)
      word_run = %(<html><body><div id="root"><p>#{'a ' * limit.div(2)}a</p></div></body></html>)

      expect(classify.call(padded)).to eq(:app_shell)
      expect(classify.call(spaced)).to eq(:app_shell)
      expect(classify.call(word_run)).to eq(:unsupported_surface)
    end

    it 'joins separate text nodes with a single space' do
      half = described_class::APP_SHELL_MAX_VISIBLE_TEXT_LENGTH / 2
      html = %(<html><body><div id="root"><p>#{'a' * half}</p><p>#{'b' * half}</p></div></body></html>)

      expect(classify.call(html)).to eq(:unsupported_surface)
    end

    it 'ignores text outside the body element' do
      html = %(<html><head><title>#{'t' * 300}</title></head><body><div id="root"></div></body></html>)

      expect(classify.call(html)).to eq(:app_shell)
    end

    it 'returns zero for a document without a body element' do
      document = Nokogiri::HTML::Document.new
      html_node = document.add_child(Nokogiri::XML::Node.new('html', document))
      html_node.add_child(Nokogiri::XML::Node.new('div', document).tap { |node| node['id'] = 'root' })

      expect(described_class.classify(document)).to eq(:app_shell)
    end
  end

  describe '.classify high-entropy' do
    let(:classify) { ->(html) { described_class.classify(Nokogiri::HTML(html)) } }

    it 'holds for hubs well beyond HIGH_ENTROPY_MIN_ANCHORS' do
      links = Array.new(described_class::HIGH_ENTROPY_MIN_ANCHORS + 5) do |index|
        %(<a href="/q/#{index}">Q #{index}</a>)
      end

      expect(classify.call("<html><body>#{links.join}</body></html>")).to eq(:high_entropy_surface)
    end

    it 'requires HIGH_ENTROPY_MIN_ANCHORS anchors', :aggregate_failures do
      limit = described_class::HIGH_ENTROPY_MIN_ANCHORS
      at_limit = Array.new(limit) { |index| %(<a href="/p/#{index}">P #{index}</a>) }.join
      below = Array.new(limit - 1) { |index| %(<a href="/p/#{index}">P #{index}</a>) }.join

      expect(classify.call("<html><body>#{at_limit}</body></html>")).to eq(:high_entropy_surface)
      expect(classify.call("<html><body>#{below}</body></html>")).to eq(:unsupported_surface)
    end
  end
end

# rubocop:enable RSpec/ExampleLength
