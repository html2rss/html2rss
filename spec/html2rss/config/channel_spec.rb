# frozen_string_literal: true

RSpec.describe Html2rss::Config::Channel do
  describe '.required_params_for_config(config)' do
    it do
      expect(
        described_class.required_params_for_config(
          { url: 'http://example.com/%<section>s/%<something>d' }
        )
      ).to be_a(Set).and include 'section', 'something'
    end
  end
end
