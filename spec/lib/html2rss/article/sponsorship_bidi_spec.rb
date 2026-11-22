# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::Sponsorship::LabelText do # rubocop:disable RSpec/SpecFilePathFormat
  wrappers = [[0x200F, 0x200F], [0x061C], [0x202B, 0x202C], [0x2067, 0x2069], [0x200E]].map do |codes|
    "#{[codes.first].pack('U')}%s#{[codes[1]].compact.pack('U*')}"
  end.freeze

  describe '.kind' do
    wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect} like the clean form", :aggregate_failures do
        expect(described_class.kind(format(wrapper, 'Anzeige'))).to be(:label)
        expect(described_class.kind(format(wrapper, 'Sponsored'))).to be(described_class.kind('Sponsored'))
        expect(described_class.kind(format(wrapper, 'Contenu'))).to be_nil
      end
    end
  end

  describe '.candidate?' do
    wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect}" do
        expect(described_class.candidate?(format(wrapper, 'Anzeige'))).to be(true)
      end
    end
  end
end
