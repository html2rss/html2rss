# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::MarkdownToHtml do
  subject { described_class.new(markdown, config: config).get }

  let(:config) do
    Html2rss::Config.new(channel: { title: 'Example: questions', url: 'https://example.com/questions' },
                         selectors: { items: {} })
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

  let(:html) do
    ['<h1>Section</h1>',
     '<p>Price: 12.34</p>',
     '<ul>',
     '<li>Item 1</li>',
     '<li>Item 2</li>',
     '</ul>',
     "<p><code>puts 'hello world'</code></p>"].join(' ')
  end

  it { is_expected.to eq html }
end
