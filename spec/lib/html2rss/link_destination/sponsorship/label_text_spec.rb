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
          expect(described_class.kind(text.unicode_normalize(form), vocabulary: all_scope)).to be(expected)
        end
      end
    end

    it 'is nil for nil' do
      expect(described_class.kind(nil, vocabulary: all_scope)).to be_nil
    end

    it 'reads the PR badge only as element text' do
      expect([described_class.kind('PR', vocabulary: all_scope),
              described_class.kind('PR', element: false, vocabulary: all_scope)]).to eq([:label, nil])
    end

    bidi_wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect} like the clean form", :aggregate_failures do
        expect(described_class.kind(format(wrapper, 'Anzeige'), vocabulary: all_scope)).to be(:label)
        expect(described_class.kind(format(wrapper, 'Sponsored'),
                                    vocabulary: all_scope)).to be(described_class.kind('Sponsored',
                                                                                       vocabulary: all_scope))
        expect(described_class.kind(format(wrapper, 'Contenu'), vocabulary: all_scope)).to be_nil
      end
    end
  end

  describe '.candidate?' do
    forms.each do |form|
      it "is true for an accented label in #{form}" do
        expect(described_class.candidate?('SPONSORISÉ'.unicode_normalize(form), vocabulary: all_scope)).to be(true)
      end
    end

    it 'is true for a PR badge and false for plain text' do
      expect([described_class.candidate?('PR', vocabulary: all_scope),
              described_class.candidate?('Harbor news', vocabulary: all_scope)]).to eq([true, false])
    end

    bidi_wrappers.each do |wrapper|
      it "reads a label wrapped in #{wrapper.inspect}" do
        expect(described_class.candidate?(format(wrapper, 'Anzeige'), vocabulary: all_scope)).to be(true)
      end
    end
  end

  describe 'a page-only language declaring the sponsorship concepts' do
    let(:xx) do
      terms = Html2rss::Vocabulary::CONCEPTS.to_h { [_1, Html2rss::Vocabulary::NONE] }
      terms.merge!(paid_label: %w[betaald-xx], ad_word: %w[advertentie-xx], element_label: %w[RK-XX])
      language = Html2rss::Vocabulary::Language.new(code: :xx, terms: terms.freeze)
      Html2rss::Vocabulary.build_scope(:xx, Html2rss::Vocabulary::ALL, own: [language])
    end
    let(:own) { described_class.build(%i[paid_label ad_word element_label].to_h { [_1, xx.own_alternation(_1)] }) }

    it 'reads each own term as a whole label through the same readings', :aggregate_failures do
      expect(own.label.match('Betaald-xx')[:paid]).to eq('Betaald-xx')
      expect(own.label.match('[advertentie-xx]')[:ad]).to eq('advertentie-xx')
      expect(own.element_label.match?('RK-XX')).to be(true)
      expect(own.element_label_word.match?('de RK-XX')).to be(true)
      expect(own.label.match?('Betaald-xx nieuws')).to be(false)
    end

    it 'leaves every shared scope on one reading without own terms', :aggregate_failures do
      shared = described_class.const_get(:BY_SCOPE).fetch(:all)

      %i[en ja de].each { expect(described_class.const_get(:BY_SCOPE).fetch(_1)).to be(shared) }
      expect(shared.label.match?('Betaald-xx')).to be(false)
      expect(described_class.const_get(:BY_SCOPE).fetch(:zh)).to be(shared)
    end
  end
end
