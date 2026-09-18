# frozen_string_literal: true

RSpec.describe Html2rss::Scoring::ContainerAssessor do
  it 'uses injected token regexps instead of LinkResolver defaults', :aggregate_failures do
    assessor = described_class.new(content_token_regexp: /custom-content/, junk_token_regexp: /custom-junk/)
    content = assessor.call(build_node(class_names: %w[custom-content]), nil, destination_facts: nil)
    junk = assessor.call(build_node(class_names: %w[custom-junk]), nil, destination_facts: nil)

    expect(content).to have_attributes(content_tokens: true, junk_tokens: false)
    expect(junk).to have_attributes(content_tokens: false, junk_tokens: true)
  end
end
