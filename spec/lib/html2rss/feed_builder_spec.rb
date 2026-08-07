# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder do
  describe '.build' do
    context 'with an unknown feed type' do
      it 'raises an ArgumentError' do
        expect do
          described_class.build(:unknown, channel: nil, articles: [])
        end.to raise_error(ArgumentError, 'Unknown feed type: unknown')
      end
    end
  end
end
