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
              described_class.attribute_kind('PR', vocabulary: all_scope)]).to eq([:label, nil])
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

  describe '.build' do
    let(:concepts) { %i[paid_label ad_word element_label] }
    let(:none) { concepts.to_h { [_1, ''] } }
    let(:own) do
      described_class.build(paid_label: 'betaald-xx', ad_word: 'advertentie-xx', element_label: 'RK-XX')
    end

    it 'reads each own term as a whole label next to the shared ones', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      expect(own.label.match('Betaald-xx')[:paid]).to eq('Betaald-xx')
      expect(own.label.match('[advertentie-xx]')[:ad]).to eq('advertentie-xx')
      expect(own.label.match('Sponsored')[:paid]).to eq('Sponsored')
      expect(own.element_label).to be_a(Regexp)
      expect(own.element_label.match?('RK-XX')).to be(true)
      expect(own.element_label.match?('PR')).to be(true)
      expect(own.element_label_word.match?('de RK-XX')).to be(true)
      expect(own.label.match?('Betaald-xx nieuws')).to be(false)
    end

    it 'adds nothing without own terms', :aggregate_failures do
      shared = described_class.build(none)

      expect(shared.label.match?('Betaald-xx')).to be(false)
      expect(shared.label.match('Sponsored')[:paid]).to eq('Sponsored')
      expect(shared.element_label.match?('PR')).to be(true)
      expect(shared.element_label_word.match?('RK-XX')).to be(false)
    end

    it 'shares one reading between every scope without own terms', :aggregate_failures do
      table = described_class.const_get(:BY_SCOPE)

      %i[en ja de all zh].each { expect(table.fetch(_1)).to be(table.fetch(:en)) }
    end
  end

  describe '.own_paid?' do
    let(:own_scope) do
      terms = Html2rss::Vocabulary::CONCEPTS.to_h { [_1, Html2rss::Vocabulary::NONE] }
      terms[:paid_label] = %w[betaald-xx]
      terms[:ad_word] = %w[advertentie-xx]
      terms[:element_label] = %w[RK-XX]
      terms[:paid_label] = %w[betaald-xx RK-XX]
      language = Html2rss::Vocabulary::Language.new(code: :xx, terms: terms.freeze)
      Html2rss::Vocabulary.build_scope(:zh, Html2rss::Vocabulary::SHARED_LANGUAGES, own: [language])
    end

    before do
      own = %i[paid_label ad_word element_label].to_h { [_1, own_scope.own_alternation(_1)] }
      stub_const("#{described_class}::BY_SCOPE",
                 described_class.const_get(:BY_SCOPE).merge(zh: described_class.build(own)))
    end

    it 'is true for a paid label only an own term states', :aggregate_failures do
      expect(described_class.own_paid?('Betaald-xx', vocabulary: own_scope)).to be(true)
      expect(described_class.own_paid?('Betaald-xx', vocabulary: all_scope)).to be(false)
    end

    it 'is false for an own paid term that is also an own element label, as the element reading wins' do
      expect(described_class.own_paid?('RK-XX', vocabulary: own_scope)).to be(false)
    end

    it 'is false for a shared element label' do
      expect(described_class.own_paid?('PR', vocabulary: own_scope)).to be(false)
    end

    it 'is false for a shared paid label, an own ad word and other text', :aggregate_failures do
      ['Sponsored', 'Advertentie-xx', 'Betaald-xx nieuws', nil].each do |text|
        expect(described_class.own_paid?(text, vocabulary: own_scope)).to be(false), text.inspect
      end
    end
  end
end
