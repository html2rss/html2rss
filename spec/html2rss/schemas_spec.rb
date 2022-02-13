# frozen_string_literal: true

RSpec.describe Html2rss::Schemas do
  it { expect(described_class::Channel).to be_a_kind_of Dry::Schema::Params }
  it { expect(described_class::Selectors).to be_a_kind_of Dry::Schema::Params }

  describe '.validate!(schema, data)' do
    context 'with invalid data' do
      it 'raises validation error'
    end
  end
end
