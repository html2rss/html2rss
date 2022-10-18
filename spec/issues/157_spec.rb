# frozen_string_literal: true

RSpec.describe 'issues/157', type: :system do
  subject do
    VCR.use_cassette('issues-157') { Html2rss.feed_from_yaml_config('spec/issues/157.yml') }
  end

  it do
    expect { subject }.not_to raise_error
  end
end
