# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::PathClassifier do
  def classifier_for(*segments)
    described_class.new(segments)
  end

  describe 'commerce / affiliate utility segments' do
    %w[
      dating jobs job career careers deals deal shopping shop trading broker
      versicherung tierversicherung insurance vergleich comparison
      partnerboerse singleboerse krypto crypto
      casinos casino kreditkarten kreditkarte kredit echtgeld vpn games kaufberater leasing
    ].each do |segment|
      it "marks /#{segment}/ routes as utility and high-confidence junk", :aggregate_failures do
        classifier = classifier_for(segment)

        expect(classifier.utility_path?).to be(true)
        expect(classifier.junk_path?).to be(true)
        expect(classifier.content_path?).to be(false)
      end
    end

    it 'marks nested affiliate routes under a commerce segment as junk', :aggregate_failures do
      classifier = classifier_for('dating', 'singles-in-berlin-heute')

      expect(classifier.utility_path?).to be(true)
      expect(classifier.junk_path?).to be(true)
      expect(classifier.content_path?).to be(false)
    end

    it 'marks commerce prefixes that embed a content token as junk, not content', :aggregate_failures do
      classifier = classifier_for('kreditkarten', 'news', 'american-express-platinum-aktion')

      expect(classifier.content_path?).to be(false)
      expect(classifier.junk_path?).to be(true)
      expect(classifier.strong_post_suffix?).to be(false)
    end

    it 'marks nested host-shaped affiliate chrome as junk', :aggregate_failures do
      classifier = classifier_for('www.bild.de', 'energieloesungen', 'photovoltaik')

      expect(classifier.junk_path?).to be(true)
      expect(classifier.content_path?).to be(false)
    end

    it 'marks /deals/ product routes as utility for commerce demotion', :aggregate_failures do
      classifier = classifier_for('deals', 'weekend-tech-sale-offers')

      expect(classifier.utility_path?).to be(true)
      expect(classifier.junk_path?).to be(true)
    end

    [
      { segments: %w[www.partner-casino.de], junk: true },
      { segments: %w[casino-bonus.example.com angebot], junk: true },
      { segments: %w[casinos echtgeld-bonus], junk: true },
      { segments: %w[kreditkarten vergleich-2026], junk: true },
      { segments: %w[politik koalition-beschliesst-neues-gesetz], junk: false },
      { segments: %w[docs v2.0], junk: false },
      { segments: %w[download file.pdf], junk: false },
      { segments: %w[assets image.jpg], junk: false }
    ].each do |example|
      it "host/commerce path #{example[:segments].join('/')} junk=#{example[:junk]}", :aggregate_failures do
        classifier = classifier_for(*example[:segments])

        expect(classifier.junk_path?).to eq(example[:junk])
      end
    end
  end

  describe 'content-like news path regression' do
    it 'does not treat /news/ article routes as utility junk', :aggregate_failures do
      classifier = classifier_for('news', '2026', 'platform-launch-notes')

      expect(classifier.content_path?).to be(true)
      expect(classifier.utility_path?).to be(false)
      expect(classifier.junk_path?).to be(false)
    end

    it 'does not demote /politik/ article slugs as commerce junk', :aggregate_failures do
      classifier = classifier_for('politik', 'koalition-beschliesst-neues-gesetz')

      expect(classifier.utility_path?).to be(false)
      expect(classifier.junk_path?).to be(false)
    end

    it 'keeps /nachrichten/ dated routes as content, not utility', :aggregate_failures do
      classifier = classifier_for('nachrichten', '2026', 'neuigkeiten-zum-produkt')

      expect(classifier.content_path?).to be(true)
      expect(classifier.utility_path?).to be(false)
      expect(classifier.junk_path?).to be(false)
    end

    it 'treats /News/ segments as content regardless of case', :aggregate_failures do
      classifier = classifier_for('News', '2026', 'platform-launch-notes')

      expect(classifier.content_path?).to be(true)
      expect(classifier.utility_path?).to be(false)
      expect(classifier.junk_path?).to be(false)
    end
  end
end
