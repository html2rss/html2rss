# frozen_string_literal: true

# Host specs define leftover_fields as a lambda: ->(html, item_selector: 'article') { Hash }
# Nokogiri adapters return ArticleExtractor hashes; SST maps Article fields onto the same keys.
RSpec.shared_examples 'article extractor leftover hygiene' do
  describe 'Novo-shaped CTA leftover' do
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">Novo Nordisk headline about research</a></h2>
          <span>Read more</span>
          <div data-category="Read more"></div>
        </article>
      HTML
    end

    it 'does not ship the CTA as description or category', :aggregate_failures do
      fields = leftover_fields.call(html)

      expect(fields[:title]).to eq('Novo Nordisk headline about research')
      expect(fields[:description]).to be_nil
      expect(fields[:categories]).not_to include('Read more')
    end
  end

  describe 'TNO-shaped field label, chip, and date leftover' do
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">TNO publishes new research findings</a></h2>
          <div class="label-type">Informatietype:</div>
          <div>News</div>
          <div>12 March 2024</div>
          <p>Researchers found a practical way to improve the measurement setup.</p>
        </article>
      HTML
    end

    it 'keeps the sentence, parses the date, and drops chrome lines', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fields = leftover_fields.call(html)

      expect(fields[:description]).to eq(
        'Researchers found a practical way to improve the measurement setup.'
      )
      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:published_at].to_date).to eq(Date.new(2024, 3, 12))
      expect(fields[:categories]).not_to include('Informatietype:')
      expect(fields[:categories]).not_to include('News')
    end
  end

  describe 'Maersk-shaped teaser leftover' do
    let(:html) do
      <<~HTML
        <article class="p-section__news__teaser">
          <h2><a href="/news/story">Maersk expands green methanol fleet</a></h2>
          <div>Press releases</div>
          <div>12 March 2024</div>
          <p>The company ordered additional dual-fuel vessels for the Asia route.</p>
        </article>
      HTML
    end

    it 'keeps the teaser and date without section/date soup', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fields = leftover_fields.call(html)

      expect(fields[:description]).to eq(
        'The company ordered additional dual-fuel vessels for the Asia route.'
      )
      expect(fields[:description]).not_to include('Press releases')
      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:categories]).not_to include('Press releases')
      expect(fields[:categories]).not_to include('Maersk expands green methanol fleet')
      expect(fields[:categories]).not_to include('12 March 2024')
    end
  end

  describe 'ASML-shaped date plus type chip leftover' do
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">ASML reports quarterly results</a></h2>
          <span>12 March 2024 - News article</span>
        </article>
      HTML
    end

    it 'sets published_at and leaves description empty', :aggregate_failures do
      fields = leftover_fields.call(html)

      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:published_at].to_date).to eq(Date.new(2024, 3, 12))
      expect(fields[:description]).to be_nil
    end
  end

  describe 'Equinor-shaped wrapping anchor with a real paragraph' do
    let(:html) do
      <<~HTML
        <a href="/news/story">
          <h2>Equinor starts new offshore wind project</h2>
          <p>The project will add capacity to the North Sea grid this decade.</p>
        </a>
      HTML
    end

    it 'keeps the paragraph as description' do
      fields = leftover_fields.call(html, item_selector: 'a')

      expect(fields[:description]).to eq(
        'The project will add capacity to the North Sea grid this decade.'
      )
    end
  end

  describe 'naive leftover date with channel time_zone' do
    let(:extractor_time_zone) { 'Europe/Berlin' }
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">Channel timezone leftover date</a></h2>
          <span>12 March 2024</span>
        </article>
      HTML
    end

    it 'interprets the leftover date in the channel time zone', :aggregate_failures do
      fields = leftover_fields.call(html)

      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:published_at].zone).to eq('+01:00')
    end
  end
end
