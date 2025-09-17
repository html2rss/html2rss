# frozen_string_literal: true

# Shared examples for post-processing configuration validation
# These examples provide common test patterns for validating post-processing configurations

RSpec.shared_examples 'validates post-processing configuration' do |selector_name|
  it "has correct post-processing configuration for #{selector_name}", :aggregate_failures do
    post_process = config[:selectors][selector_name][:post_process]
    expect(post_process).to be_an(Array)
    expect(post_process.first).to include(:name)
  end
end

RSpec.shared_examples 'validates description post-processing' do
  it_behaves_like 'validates post-processing configuration', :description
end

RSpec.shared_examples 'validates published_at post-processing' do
  it_behaves_like 'validates post-processing configuration', :published_at
end
