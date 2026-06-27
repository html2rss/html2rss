# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::MarkdownToHtml do
  subject { described_class.new(markdown, context).get }

  let(:html) do
    "<h1>Section</h1>\n\n<p>Price: 12.34</p>\n\n" \
      "<ul>\n<li>Item 1</li>\n<li>Item 2</li>\n</ul>\n\n" \
      "<p><code>puts 'hello world'</code></p>"
  end
  let(:markdown) do
    <<~MD
      # Section

      Price: 12.34

      - Item 1
      - Item 2

      `puts 'hello world'`
    MD
  end
  let(:config) do
    { channel: { title: 'Example: questions', url: 'https://example.com/questions' },
      selectors: { items: {} } }
  end
  let(:context) { Html2rss::Selectors::Context.new(config:, options: {}) }

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  it { is_expected.to eq html }
end
