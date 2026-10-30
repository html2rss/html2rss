# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::PathClassifier do
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

  describe '#trusted_post_context?' do
    let(:trusted) do
      lambda do |limit, *segments|
        classifier_for(*segments).instance_eval { trusted_post_context?(limit) }
      end
    end

    it 'accepts content, year, or press context before the limit', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(trusted.call(0, 'blog')).to be(false)
      expect(trusted.call(-1, 'blog')).to be(false)
      expect(trusted.call(1, 'blog')).to be(true)
      expect(trusted.call(1, 'Blog')).to be(true)
      expect(trusted.call(1, 'misc')).to be(false)
      expect(trusted.call(1, '123')).to be(false)
      expect(trusted.call(1, 'x2026')).to be(false)
      expect(trusted.call(1, '2026 ')).to be(false)
      expect(trusted.call(1, '2026')).to be(true)
      expect(trusted.call(1, 'press')).to be(true)
      expect(trusted.call(1, 'Press')).to be(true)
      expect(trusted.call(1, 'misc', 'blog')).to be(false)
      expect(trusted.call(2, 'misc', 'blog')).to be(true)
      expect(trusted.call(2, 'blog', 'misc')).to be(true)
      expect(trusted.call(2, 'about', 'blog')).to be(false)
    end
  end

  describe 'route flag matrix' do
    # Flags are content, utility, vanity, taxonomy, shallow, strong post suffix, junk, utility destination.
    let(:route_flags) do
      lambda do |classifier|
        %i[content_path? utility_path? vanity_path? taxonomy_path? shallow? strong_post_suffix? junk_path?
           utility_destination?].map { |predicate| classifier.public_send(predicate) ? 't' : 'f' }.join
      end
    end

    {
      %w[news 2026 2027] => 'tfffftff', %w[news 2026 about] => 'ttffffff', %w[news 2026 join] => 'tttfffff',
      %w[news 2026 Platform] => 'tfffffff', %w[news 2026-x] => 'tfffftff', %w[news 2026 slug-a-b] => 'tfffftff',
      %w[news slug-a-b-c] => 'tfffftff', %w[news about-us-team] => 'tfffftff', %w[news x-y-z] => 'tfffftff',
      %w[about news 2026 slug-a-b-c] => 'ftfffftf', %w[misc press big-news-story-here] => 'ffffftff',
      %w[misc press Big-news-story] => 'ffffftff', %w[misc blog] => 'tfffffff', %w[misc blog about] => 'ttffffff',
      %w[blog contact-us-today] => 'tfffftff', %w[blog 2026 contact-us-today] => 'tfffftff',
      %w[blog page-two] => 'tfffffff', %w[misc 2026] => 'ffffffff', %w[misc join plan-a-b] => 'fttfffft',
      %w[join membership-plan-a] => 'fttfffft', %w[plus] => 'fttftftt', %w[subscribe] => 'fttftftt',
      %w[premium] => 'fttftftt', %w[pricing] => 'fttftftt', %w[category] => 'ftfttftt',
      %w[tag foo] => 'ftftfftt', %w[topic x y] => 'ftftfftt', %w[shop] => 'ftfftftt',
      %w[shop products] => 'ftfffftt', %w[shop products item-a-b-c] => 'ftfffftf', %w[docs guide] => 'ffffffff',
      %w[docs v2.0] => 'ffffffff', %w[download file.pdf] => 'ffffffff', %w[assets image.jpg] => 'ffffffff',
      %w[www.example.com] => 'fffftftt', %w[sub.example.co.uk story] => 'fffffftt',
      %w[www.bild.de energieloesungen photovoltaik] => 'fffffftf', %w[misc www.bild.de] => 'fffftftf',
      %w[misc casino-bonus.example.com] => 'fffftftf', %w[casino-bonus.example.com angebot] => 'fffffftt',
      %w[archive 2026 news-slug-a] => 'ftfffftf', %w[archive 2026] => 'ftfffftt',
      %w[comments 2026 big-news-x] => 'ftfffftf', %w[press 2026-x] => 'tfffftff',
      %w[politik 2026 gesetz-a-b] => 'tfffftff', %w[politik gesetz-a-b-c] => 'ffffffff',
      %w[newsroom annual-report-2026] => 'ffffftff', %w[press newsroom news-today-one] => 'ffffftff',
      %w[datenschutz erklaerung] => 'ftfffftt', %w[nachrichten] => 'tffftfff',
      %w[nachrichten 2026 neuigkeiten-zum-produkt] => 'tfffftff', %w[artikel 2026 eine-geschichte-b] => 'tfffftff',
      %w[misc about contact-us-today-x] => 'ftfffftf', %w[about contact] => 'ftfftftt', %w[news about] => 'ttfftfff',
      %w[news dating] => 'ttfftfff', %w[misc news-tag-1] => 'ffffffff', %w[123 news slug-a-b-c] => 'tfffftff',
      %w[news 2026 a-b-c 2026] => 'tfffftff', [] => 'fffftfff', %w[widget-xyz-detail] => 'fffftfff',
      %w[2026] => 'fffftfff', %w[misc 2026 x] => 'tfffffff', %w[misc blog 2026] => 'tfffftff',
      %w[news about big-story-slug-x] => 'ttffftff', %w[news big-story-slug-x about] => 'ttffffff',
      %w[news 2026 plans] => 'tttfffff', %w[news 2026 dating] => 'ttffffff', %w[about x-y] => 'ftfffftt',
      %w[about contact x-y] => 'ftfffftt', %w[dating x-y-z-w] => 'ftfffftt', %w[x-y about z-w] => 'ftfffftf',
      %w[news 2026 about-x-y] => 'tfffftff', %w[misc about x-y] => 'ftfffftf', %w[docs x-y] => 'ffffffff',
      %w[archive 2026 x] => 'ftfffftf', %w[x-y category z-w] => 'ftftfftt', %w[x-y about] => 'ftfftftt',
      %w[x-y plus] => 'fttfffft', %w[misc press dating big-news-story-here] => 'ftffftff'
    }.each do |segments, flags|
      it "flags /#{segments.join('/')} as #{flags}", :aggregate_failures do
        classifier = classifier_for(*segments)

        expect(classifier.segments).to eq(segments)
        expect(route_flags.call(classifier)).to eq(flags)
      end
    end
  end
end
