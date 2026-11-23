# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::Sponsorship::LabelText do
  bidi_wrappers = [[0x200F, 0x200F], [0x061C], [0x202B, 0x202C], [0x2067, 0x2069], [0x200E]].map do |codes|
    "#{[codes.first].pack('U')}%s#{[codes[1]].compact.pack('U*')}"
  end.freeze
  forms = %i[nfc nfd]

  describe '.kind' do
    {
      'SPONSORISÉ' => :paid_label, 'Contenu sponsorisé' => :paid_label, 'MATERIAŁ PARTNERA' => :paid_label,
      'Sponsrat Innehåll' => :paid_label, 'PUBLICITÉ' => :label, 'PUBBLICITÀ' => :label, 'Publicité' => :label,
      'Contenu' => nil
    }.each do |text, expected|
      forms.each do |form|
        it "is #{expected.inspect} for #{text.inspect} in #{form}" do
          expect(described_class.kind(text.unicode_normalize(form))).to be(expected)
        end
      end
    end

    it 'is nil for nil' do
      expect(described_class.kind(nil)).to be_nil
    end

    it 'reads the PR badge only as element text' do
      expect([described_class.kind('PR'), described_class.kind('PR', element: false)]).to eq([:label, nil])
    end

    bidi_wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect} like the clean form", :aggregate_failures do
        expect(described_class.kind(format(wrapper, 'Anzeige'))).to be(:label)
        expect(described_class.kind(format(wrapper, 'Sponsored'))).to be(described_class.kind('Sponsored'))
        expect(described_class.kind(format(wrapper, 'Contenu'))).to be_nil
      end
    end
  end

  describe '.candidate?' do
    forms.each do |form|
      it "is true for an accented label in #{form}" do
        expect(described_class.candidate?('SPONSORISÉ'.unicode_normalize(form))).to be(true)
      end
    end

    it 'is true for a PR badge and false for plain text' do
      expect([described_class.candidate?('PR'), described_class.candidate?('Harbor news')]).to eq([true, false])
    end

    bidi_wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect}" do
        expect(described_class.candidate?(format(wrapper, 'Anzeige'))).to be(true)
      end
    end
  end
end
