# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::Sponsorship::LabelText do
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
  end
end
