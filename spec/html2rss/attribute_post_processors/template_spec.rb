# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::Template do
  subject { described_class.new('Hi', options:, item:).get }

  # An instance_double does not work with method_missing.
  # rubocop:disable RSpec/VerifiedDoubles
  let(:item) { double(Html2rss::Item) }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    allow(item).to receive_messages(name: 'My name', author: 'Slim Shady', returns_nil: nil)
  end

  context 'with methods present (simple formatting)' do
    let(:options) { { string: '%s! %s is %s! %s', methods: %i[self name author returns_nil] } }

    it { is_expected.to eq 'Hi! My name is Slim Shady! ' }
  end

  context 'with methods absent (complex formatting)' do
    let(:options) { { string: '%{self}! %<name>s is %{author}! %{returns_nil}' } } # rubocop:disable Style/FormatStringToken

    it { is_expected.to eq 'Hi! My name is Slim Shady! ' }
  end
end
