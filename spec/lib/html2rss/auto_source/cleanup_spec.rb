# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Cleanup do
  let(:url) { Html2rss::Url.from_absolute('http://example.com') }
  let(:articles) do
    [
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article0', 'http://example.com'),
                      title: 'Valid Article One'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article1', 'http://example.com'),
                      title: 'Valid Article Two'),
      instance_double(Html2rss::Article,
                      valid?: false,
                      url: Html2rss::Url.from_relative('http://example.com/article2', 'http://example.com'),
                      title: 'Invalid Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://otherdomain.com/article3', 'http://example.com'),
                      title: 'Different Domain Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('ftp://example.com/article4', 'http://example.com'),
                      title: 'Non-HTTP Article'),
      instance_double(Html2rss::Article,
                      valid?: true,
                      url: Html2rss::Url.from_relative('http://example.com/article5', 'http://example.com'),
                      title: 'Short')
    ]
  end

  describe '.call' do
    subject(:result) { described_class.call(articles, url:, keep_different_domain:) }

    let(:cleaned) { result.articles }
    let(:keep_different_domain) { false }

    # rubocop:disable RSpec/ExampleLength -- articles + multi-reason tallies
    it 'removes invalid articles and tallies the drop', :aggregate_failures do
      expect(cleaned).not_to include(articles[2])
      expect(result.drop_tallies).to include(
        'invalid' => 1,
        'low_word_count' => 1,
        'different_domain' => 1,
        'bad_scheme' => 1
      )
    end
    # rubocop:enable RSpec/ExampleLength

    context 'with duplicated articles' do
      let(:duplicated_url_article) do
        instance_double(Html2rss::Article,
                        valid?: true,
                        url: articles.first.url,
                        title: 'Duplicated Article Title')
      end

      before { articles << duplicated_url_article }

      it 'removes duplicate articles by URL', :aggregate_failures do
        expect(cleaned).not_to include(duplicated_url_article)
        expect(cleaned.first.url).to eq(duplicated_url_article.url)
        expect(result.drop_tallies['duplicate_url']).to eq(1)
      end
    end

    context 'when URLs differ only by fragment' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/news') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/story-one'),
                          title: 'First Story Title Here'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/story-one#comments'),
                          title: 'Same Story Different Fragment'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/news#section'),
                          title: 'Self Link With Fragment Text'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/news'),
                          title: 'Exact Self Link Title Words')
        ]
      end

      it 'dedupes fragment variants and rejects page self-links', :aggregate_failures do
        expect(cleaned.map { |article| article.url.to_s }).to eq(['http://example.com/story-one'])
        expect(cleaned.size).to eq(1)
        expect(result.drop_tallies).to include('duplicate_url' => 2, 'self_link' => 1)
      end
    end

    it 'keeps only HTTP and HTTPS articles' do
      expect(cleaned).not_to include(articles[4])
    end

    context 'when keep_different_domain is false' do
      it 'removes articles from different domains' do
        expect(cleaned).not_to include(articles[3])
      end
    end

    context 'when keep_different_domain is true' do
      let(:keep_different_domain) { true }

      it 'keeps articles from different domains' do
        different_domain_article = articles[3]
        expect(cleaned).to include(different_domain_article)
      end
    end

    it 'rejects titles with fewer than three words' do
      expect(cleaned).not_to include(articles[5])
    end

    context 'with excluded destination classes' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/news/deep-story-slug-here'),
                          title: 'Deep Story Slug Here Extra'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/dating/singles-in-berlin'),
                          title: 'Singles In Berlin Find Love'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/dating/singleboerse-vergleich/partnersuche-ab-50'),
                          title: 'Partnersuche Ab Fifty Years Old'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/jobs/stellenangebote/berlin'),
                          title: 'Jobs Stellenangebote Berlin Extra'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/deals/weekend-tech-sale'),
                          title: 'Weekend Tech Sale Offers Now'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/kreditkarten/news/amex-offer-slug'),
                          title: 'Amex Offer Slug Extra Words'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/www.partner.de/energieloesungen/pv'),
                          title: 'Partner Energy Solutions Extra Words'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/subscribe'),
                          title: 'Subscribe To Our Newsletter Today'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('https://example.com/category/tech'),
                          title: 'Tech Category Listing Page Words')
        ]
      end

      it 'hard-excludes commerce affiliate utility and taxonomy routes', :aggregate_failures do
        expect(cleaned.map { |article| article.url.to_s })
          .to eq(['https://example.com/news/deep-story-slug-here'])
        expect(result.drop_tallies['excluded_destination']).to be >= 1
      end
    end

    context 'with junk and acceptable titles' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/list') }

      # Table-driven keep/reject via public junk_reason + Cleanup.call (not private send).
      [
        { title: 'A valid title', reason: nil },
        { title: 'Getty Images', reason: :credit },
        { title: 'Photo: Reuters', reason: :credit },
        { title: 'lucy.smith.token', reason: :cms_token },
        { title: 'methode-article-slug', reason: :cms_token },
        { title: nil, reason: nil },
        { title: 'Reuters reports major breakthrough today', reason: nil },
        { title: 'Courtesy Casie Ellison via pool camera', reason: :credit },
        { title: 'Courtesy Call Yields Breakthrough Deal', reason: nil },
        { title: 'US Navy/Handout/Reuters', reason: :credit },
        { title: "Analysis•\nJim Lo Scalzo/Reuters", reason: :credit },
        { title: 'Live Updates• AFP desk report line', reason: :credit },
        { title: 'v_m_hw_pass', reason: :slug },
        { title: 'story-has-edit-branch', reason: :slug },
        { title: 'Created from Template ID TMG-44192 extra', reason: :template },
        { title: 'Clipped From Video', reason: :video_chrome },
        { title: 'Video• 2:23 Watch the full clip now', reason: :video_chrome },
        { title: 'Video: How the Fed raised rates today', reason: nil },
        { title: 'breakdancerin-raygun-geht-weiter-110168077', reason: :slug },
        { title: 'Breakdancerin Raygun Geht Weiter 110168077', reason: :titleized_path },
        { title: '2026 08 16 World Europe Some Article Slug', reason: :date_prefix },
        { title: 'Hello {{article_title}} world token', reason: :template },
        { title: 'Jobs in Berlin', reason: nil },
        { title: '5 Wahrheiten über die deutsche Leichtathletik', reason: nil },
        # First-match pin: agency-only credit beats slug shape for hyphenated CMS ids.
        { title: 'AFP', reason: :credit }
      ].each_with_index do |example, index|
        it "returns junk_reason #{example[:reason].inspect} for #{example[:title].inspect}" do
          expect(described_class.junk_reason(example[:title])).to eq(example[:reason])
        end

        # rubocop:disable RSpec/ExampleLength -- keep + reason tally contract
        it "keeps=#{example[:reason].nil?} for #{example[:title].inspect}", :aggregate_failures do
          article = instance_double(Html2rss::Article, valid?: true, title: example[:title],
                                                       url: Html2rss::Url.from_absolute("http://example.com/t#{index}"))
          call_result = described_class.call([article], url:)
          expect(call_result.articles.map(&:title).include?(example[:title])).to eq(example[:reason].nil?)
          next if example[:reason].nil?

          expect(call_result.drop_tallies[example[:reason].to_s]).to eq(1)
        end
        # rubocop:enable RSpec/ExampleLength
      end
    end

    context 'with non-Latin titles' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/list') }
      let(:articles) do
        [
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/ru'),
                          title: 'Привет мир сегодня'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/ar'),
                          title: 'مرحبا بالعالم اليوم'),
          instance_double(Html2rss::Article,
                          valid?: true,
                          url: Html2rss::Url.from_absolute('http://example.com/zh'),
                          title: '你好世界')
        ]
      end

      it 'counts Unicode words with the fixed three-word gate', :aggregate_failures do
        titles = cleaned.map(&:title)
        expect(titles).to include('Привет мир сегодня', 'مرحبا بالعالم اليوم')
        expect(titles).not_to include('你好世界')
        expect(result.drop_tallies['low_word_count']).to eq(1)
      end
    end
  end
end
