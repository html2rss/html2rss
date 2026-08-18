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

  describe 'heading-only item with sibling teaser and date' do
    let(:html) do
      <<~HTML
        <div class="card">
          <h3><a href="/news/story">Heading only title about the story</a></h3>
          <p>Sibling teaser that lives beside the heading.</p>
          <time datetime="2024-03-12T09:00:00Z">12 March 2024</time>
        </div>
      HTML
    end

    it 'fills missing leftover fields from the parent card', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h3')

      expect(fields[:title]).to eq('Heading only title about the story')
      expect(fields[:description]).to eq('Sibling teaser that lives beside the heading.')
      expect(fields[:description]).not_to eq(fields[:title])
      expect(fields[:published_at]).to be_a(DateTime)
    end
  end

  describe 'span-wrapped sibling list links' do
    let(:html) do
      <<~HTML
        <div>
          <a href="/news/one"><span>Title One About The First Story</span></a>
          <a href="/news/two"><span>Title Two About The Second Story</span></a>
        </div>
      HTML
    end

    it 'does not use a sibling title as description', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'a')

      expect(fields[:title]).to eq('Title One About The First Story')
      expect(fields[:description]).to be_nil
      expect(fields[:description].to_s).not_to include('Title Two')
    end
  end

  describe 'heading items sharing a section' do
    let(:html) do
      <<~HTML
        <section>
          <h2><a href="/news/one">Title One About The First Story</a></h2>
          <h2><a href="/news/two">Title Two About The Second Story</a></h2>
        </section>
      HTML
    end

    it 'does not use the next heading as description', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h2')

      expect(fields[:title]).to eq('Title One About The First Story')
      expect(fields[:description]).to be_nil
      expect(fields[:description].to_s).not_to include('Title Two')
    end
  end

  describe 'heading wrapped in a header landmark' do
    let(:html) do
      <<~HTML
        <div class="card">
          <header>
            <h3><a href="/news/story">Heading wrapped by header chrome</a></h3>
          </header>
          <p>Teaser outside the header wrapper.</p>
          <time datetime="2024-03-12T09:00:00Z">12 March 2024</time>
        </div>
      HTML
    end

    it 'fills leftover fields from the outer card', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h3')

      expect(fields[:description]).to eq('Teaser outside the header wrapper.')
      expect(fields[:published_at]).to be_a(DateTime)
    end
  end

  describe 'heading wrapped in a title-wrap div' do
    let(:html) do
      <<~HTML
        <div class="card">
          <div class="title-wrap">
            <h3><a href="/news/story">Heading wrapped by a title div</a></h3>
          </div>
          <p>Teaser outside the title wrapper.</p>
          <time datetime="2024-03-12T09:00:00Z">12 March 2024</time>
        </div>
      HTML
    end

    it 'fills leftover fields from the outer card', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h3')

      expect(fields[:description]).to eq('Teaser outside the title wrapper.')
      expect(fields[:published_at]).to be_a(DateTime)
    end
  end

  describe 'News taxonomy chip on a category class' do
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">Story with a news taxonomy tag</a></h2>
          <span class="post-tag">News</span>
          <p>A real teaser sentence about the story.</p>
        </article>
      HTML
    end

    it 'keeps News as a category and the teaser as description', :aggregate_failures do
      fields = leftover_fields.call(html)

      expect(fields[:categories]).to include('News')
      expect(fields[:description]).to eq('A real teaser sentence about the story.')
    end
  end

  describe 'invalid channel time_zone' do
    let(:extractor_time_zone) { 'Not/AZone' }
    let(:html) do
      <<~HTML
        <article>
          <h2><a href="/news/story">Invalid timezone leftover date</a></h2>
          <span>12 March 2024</span>
        </article>
      HTML
    end

    it 'still parses the leftover date', :aggregate_failures do
      fields = leftover_fields.call(html)

      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:published_at].to_date).to eq(Date.new(2024, 3, 12))
    end
  end

  describe 'DIIS-shaped heading-link item' do
    let(:html) do
      <<~HTML
        <article class="research-card">
          <h3><a href="/research/publication-one">Title of the publication about research</a></h3>
          <p>Sibling teaser that lives beside the heading link.</p>
          <time datetime="2024-03-12T09:00:00Z">12 March 2024</time>
        </article>
      HTML
    end

    it 'walks from h3 a to the card for teaser, date, and url', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h3 a')

      expect(fields[:title]).to eq('Title of the publication about research')
      expect(fields[:description]).to eq('Sibling teaser that lives beside the heading link.')
      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:url].to_s).to include('/research/publication-one')
    end
  end

  describe 'heading-link plus same-href Read more' do
    let(:html) do
      <<~HTML
        <div class="card">
          <h3><a href="/news/story">Heading title about the story</a></h3>
          <p>Sibling teaser that lives beside the heading.</p>
          <a href="/news/story">Read more</a>
          <time datetime="2024-03-12T09:00:00Z">12 March 2024</time>
        </div>
      HTML
    end

    it 'does not treat title plus CTA as two articles', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'h3 a')

      expect(fields[:title]).to eq('Heading title about the story')
      expect(fields[:description]).to eq('Sibling teaser that lives beside the heading.')
      expect(fields[:description].to_s).not_to eq('Read more')
      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:url].to_s).to include('/news/story')
    end
  end

  describe 'Nokia-shaped wrapping anchor with pipe date' do
    let(:html) do
      <<~HTML
        <a href="/news/story">
          <h2>Nokia headline about the product launch</h2>
          <span>August 06 , 2026 | 13:00 PM Europe/Amsterdam</span>
        </a>
      HTML
    end

    it 'parses the calendar day and drops the pipe clock line', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'a')

      expect(fields[:title]).to eq('Nokia headline about the product launch')
      expect(fields[:published_at]).to be_a(DateTime)
      expect(fields[:published_at].to_date).to eq(Date.new(2026, 8, 6))
      expect(fields[:description]).to be_nil
    end
  end

  describe 'Telenor-shaped wrapping anchor with bullet juli date' do
    let(:html) do
      <<~HTML
        <a href="/news/story">
          <h2>Telenor headline about the network upgrade</h2>
          <span>Press release • 16 juli, 2026</span>
        </a>
      HTML
    end

    it 'drops the type-chip date line from description', :aggregate_failures do
      fields = leftover_fields.call(html, item_selector: 'a')

      expect(fields[:title]).to eq('Telenor headline about the network upgrade')
      expect(fields[:description]).to be_nil
      expect(fields[:description].to_s).not_to include('juli')
    end
  end
end
