# frozen_string_literal: true

RSpec.shared_examples 'example feed channel metadata' do |title:, link:, language: nil|
  it 'publishes the configured channel metadata', :aggregate_failures do
    expect(feed.channel.title).to eq(title)
    expect(feed.channel.link).to eq(link)
    expect(feed.channel.language).to eq(language) if language
  end
end
