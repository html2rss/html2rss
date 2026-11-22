# frozen_string_literal: true

RSpec.describe Html2rss::Article::Title do
  # Each wrapper holds %s between direction marks (LRM/RLM, ALM, RLE..PDF, RLI..PDI).
  wrappers = [[0x200F, 0x200F], [0x061C], [0x202B, 0x202C], [0x2067, 0x2069], [0x200E]].map do |codes|
    "#{[codes.first].pack('U')}%s#{[codes[1]].compact.pack('U*')}"
  end.freeze
  let(:rlm) { [0x200F].pack('U') }
  let(:zwnj) { [0x200C].pack('U') }

  describe '.noise_piece?' do
    wrappers.each do |wrapper|
      it "reads a marker and a label wrapped in #{wrapper.inspect} like the clean form", :aggregate_failures do
        expect(described_class.noise_piece?(format(wrapper, 'Video'))).to be(true)
        expect(described_class.noise_piece?(format(wrapper, 'Section:'))).to be(true)
        expect(described_class.noise_piece?(format(wrapper, '10:00'))).to be(true)
        expect(described_class.noise_piece?(format(wrapper, 'Conflict'))).to be(false)
      end
    end
  end

  describe '.date_piece?' do
    wrappers.each do |wrapper|
      it "reads a date wrapped in #{wrapper.inspect}" do
        expect(described_class.date_piece?(format(wrapper, '11月12日'))).to be(true)
      end
    end
  end

  describe '.clock_piece?' do
    wrappers.each do |wrapper|
      it "reads a clock wrapped in #{wrapper.inspect}" do
        expect(described_class.clock_piece?(format(wrapper, '10:00'))).to be(true)
      end
    end
  end

  describe '.headline_noise_piece?' do
    wrappers.each do |wrapper|
      it "reads a date and a label wrapped in #{wrapper.inspect}", :aggregate_failures do
        expect(described_class.headline_noise_piece?(format(wrapper, '11月12日 16:42'))).to be(true)
        expect(described_class.headline_noise_piece?(format(wrapper, 'Section:'))).to be(true)
      end
    end
  end

  describe '.compose' do
    it 'drops a kicker that is only a marker wrapped in marks and keeps the headline verbatim' do
      headline = "#{rlm}Headline#{rlm}"
      expect(described_class.compose(headline, kicker: "#{rlm}Video#{rlm}")).to eq(headline)
    end

    it 'keeps a ZWNJ inside a Persian word, and the marks, in the output' do
      kicker = "#{rlm}kicker#{rlm}"
      expect(described_class.compose("a#{zwnj}b", kicker:)).to eq("#{kicker}: a#{zwnj}b")
    end
  end
end
