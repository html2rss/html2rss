# frozen_string_literal: true

RSpec.shared_examples 'compact media renderer html' do |tag:, url:, type:, open_tag:|
  it "renders compact #{tag} html with escaped attributes", :aggregate_failures do
    html = described_class.new(url:, type:).to_html
    escaped_url = url.gsub('&', '&amp;')
    expected_html = [open_tag, %(<source src="#{escaped_url}" type="#{type}">), "</#{tag}>"].join

    expect(html).to eq(expected_html)
    expect(html).not_to include("\n")
  end
end

RSpec.shared_examples 'image renderer empty title attrs' do |title:|
  it 'renders an img tag with empty alt and title attributes', :aggregate_failures do
    html = described_class.new(url: 'https://example.com/image.jpg', title:).to_html

    expect(html).to include('src="https://example.com/image.jpg"')
    expect(html).to include('alt=""')
    expect(html).to include('title=""')
    expect(html).to include('loading="lazy"')
    expect(html).to include('referrerpolicy="no-referrer"')
    expect(html).to include('decoding="async"')
    expect(html).to include('crossorigin="anonymous"')
    expect(html).not_to include("\n")
  end
end
